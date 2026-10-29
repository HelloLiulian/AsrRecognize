import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

/// 本地 Qwen3-ASR 录音会话：麦克风采集、能量 VAD 分段、串行识别、文本拼接。
@MainActor
final class LocalTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var partialText = ""
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var startDate: Date?
    @Published private(set) var audioFileName: String?

    @Published private(set) var isPrepared = false
    @Published private(set) var isDraining = false
    @Published private(set) var loadFraction: Double = 0
    @Published private(set) var statusText = "本地模型未加载"

    private let engine: Qwen3CoreMLEngine
    private let audioEngine = AVAudioEngine()
    private let sink = AudioFileSink()
    private let converter = Audio16kConverter()
    private let vad = VoiceActivityDetector()
    private let droppedFlag = FlagBox()

    private var worker: Task<Void, Never>?
    private var streamContinuation: AsyncStream<[Float]>.Continuation?
    private var timer: Timer?
    private var accumulated: TimeInterval = 0
    private var sessionStartedAt: Date?
    private var audioURL: URL?
    private var tapInstalled = false
    private var hasOverflowed = false
    private var languageHint = "chinese"
    private var memoryObserver: NSObjectProtocol?

    init(engine: Qwen3CoreMLEngine = Qwen3CoreMLEngine()) {
        self.engine = engine
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }

    // MARK: - Lifecycle

    func start(language: String) async {
        guard !isRecording else { return }
        errorMessage = nil
        segments = []
        partialText = ""
        elapsed = 0
        accumulated = 0
        hasOverflowed = false
        startDate = nil
        languageHint = Self.languageHint(for: language)

        if !isPrepared {
            await prepareIfNeeded()
        }
        guard isPrepared else { return }

        let micOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micOK else {
            errorMessage = "未获得麦克风权限。请前往「设置 › 隐私与安全性 › 麦克风」开启后重试。"
            return
        }

        do {
            try startCapture()
        } catch {
            cleanupAfterFailedStart()
            errorMessage = "无法开始录音：\(error.localizedDescription)"
        }
    }

    func prepareIfNeeded() async {
        guard !isPrepared else { return }
        guard LocalModelAssets.isBundled else {
            statusText = "模型未打包"
            errorMessage = "当前安装包里没有本地 Qwen3 模型，请改用系统语音识别。"
            return
        }
        loadFraction = 0
        statusText = "首次加载模型可能较慢…"
        do {
            try await engine.prepare { [weak self] fraction, message in
                Task { @MainActor in
                    guard let self else { return }
                    self.loadFraction = fraction
                    self.statusText = message
                }
            }
            isPrepared = true
            loadFraction = 1
            statusText = "模型就绪"
        } catch {
            statusText = "模型不可用"
            errorMessage = "本地模型加载失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Pause / resume

    func pause() {
        guard isRecording, !isPaused else { return }
        if let sessionStartedAt {
            accumulated += Date().timeIntervalSince(sessionStartedAt)
        }
        sessionStartedAt = nil
        elapsed = accumulated
        isPaused = true
        audioEngine.pause()
        removeTap()
        level = 0
    }

    func resume() {
        guard isRecording, isPaused else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let format = audioEngine.inputNode.outputFormat(forBus: 0)
            installTap(format: format)
            try audioEngine.start()
            isPaused = false
            sessionStartedAt = Date()
        } catch {
            errorMessage = "无法恢复录音：\(error.localizedDescription)"
            stopImmediately()
        }
    }

    // MARK: - Stop

    /// 停止录音并等待队列清空；若队列曾溢出，从录音文件重建全文。
    func stopAndFinish() async {
        guard isRecording else { return }
        isDraining = true
        stopCapture()

        if let tail = vad.flush(), let continuation = streamContinuation {
            if case .dropped = continuation.yield(tail) {
                droppedFlag.set()
            }
        }
        streamContinuation?.finish()
        streamContinuation = nil
        await worker?.value
        worker = nil

        if droppedFlag.take() {
            hasOverflowed = true
        }
        if hasOverflowed, let audioURL {
            await rebuildTranscript(from: audioURL)
        }
        isDraining = false
    }

    /// 立即停止，不等待剩余队列（取消、退场、出错时使用）。
    func stopImmediately() {
        guard isRecording else { return }
        stopCapture()
        streamContinuation?.finish()
        streamContinuation = nil
        worker?.cancel()
        worker = nil
    }

    func discard() {
        stopImmediately()
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
        audioFileName = nil
        segments = []
        partialText = ""
        elapsed = 0
        accumulated = 0
        startDate = nil
        level = 0
        errorMessage = nil
    }

    // MARK: - Capture

    private func startCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "LocalTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "没有检测到可用的麦克风输入"]
            )
        }

        let url = AudioStorage.makeNewFileURL()
        try sink.open(url: url, format: format)
        audioURL = url
        audioFileName = url.lastPathComponent

        startWorker()
        installTap(format: format)

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        isPaused = false
        startDate = Date()
        sessionStartedAt = Date()
        startTimer()
    }

    private func installTap(format: AVAudioFormat) {
        guard !tapInstalled, let continuation = streamContinuation else { return }

        let sink = self.sink
        let converter = self.converter
        let vad = self.vad
        let droppedFlag = self.droppedFlag

        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            sink.write(buffer)

            let samples = converter.convert(buffer)
            guard !samples.isEmpty else { return }
            for segment in vad.feed(samples) {
                if case .dropped = continuation.yield(segment) {
                    droppedFlag.set()
                }
            }

            let level = Self.level(from: samples)
            Task { @MainActor [weak self] in
                self?.level = level
            }
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func stopCapture() {
        if !isPaused, let sessionStartedAt {
            accumulated += Date().timeIntervalSince(sessionStartedAt)
        }
        sessionStartedAt = nil
        elapsed = accumulated
        isRecording = false
        isPaused = false

        timer?.invalidate()
        timer = nil

        audioEngine.stop()
        removeTap()
        sink.close()
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanupAfterFailedStart() {
        audioEngine.stop()
        removeTap()
        sink.close()
        streamContinuation?.finish()
        streamContinuation = nil
        worker?.cancel()
        worker = nil
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
        audioFileName = nil
        isRecording = false
        isPaused = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Worker

    private func startWorker() {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .bufferingOldest(4)
        )
        streamContinuation = continuation

        let engine = self.engine
        let hint = languageHint
        worker = Task { [weak self] in
            for await samples in stream {
                do {
                    let text = try await engine.transcribe(samples: samples, language: hint)
                    self?.appendSegment(text)
                } catch TranscriptionEngineError.emptyResult {
                    continue
                } catch {
                    self?.errorMessage = "识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func appendSegment(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(TranscriptSegment(text: trimmed, timestamp: elapsed))
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    private func updateElapsed() {
        guard isRecording, !isPaused, let sessionStartedAt else { return }
        elapsed = accumulated + Date().timeIntervalSince(sessionStartedAt)
    }

    // MARK: - Memory

    private func handleMemoryWarning() {
        guard !isRecording else { return }
        Task {
            await engine.unload()
            isPrepared = false
            statusText = "内存紧张，模型已释放"
        }
    }

    // MARK: - Rebuild from recording

    private func rebuildTranscript(from url: URL) async {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let vad = VoiceActivityDetector()
        var rebuilt: [TranscriptSegment] = []
        var offset: TimeInterval = 0
        let capacity: AVAudioFrameCount = 16_000

        func append(_ segment: [Float], timestamp: TimeInterval) async {
            guard let text = try? await engine.transcribe(samples: segment, language: languageHint) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            rebuilt.append(TranscriptSegment(text: trimmed, timestamp: timestamp))
        }

        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                break
            }
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            if buffer.frameLength == 0 { break }

            let samples = Self.floatSamples(from: buffer)
            for segment in vad.feed(samples) {
                await append(segment, timestamp: offset)
            }
            offset += Double(buffer.frameLength) / format.sampleRate
        }

        if let tail = vad.flush() {
            await append(tail, timestamp: offset)
        }

        if !rebuilt.isEmpty {
            segments = rebuilt
        }
    }

    // MARK: - Helpers

    private static func languageHint(for code: String) -> String {
        code.hasPrefix("zh") ? "chinese" : "english"
    }

    private static func level(from samples: [Float]) -> CGFloat {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for value in samples {
            sum += value * value
        }
        let rms = sqrt(sum / Float(samples.count))
        let decibels = 20 * log10(max(rms, 0.00001))
        let normalized = max(0, min(1, (decibels + 55) / 55))
        return CGFloat(normalized)
    }

    private static func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        if let data = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }
        if let data = buffer.int16ChannelData?[0] {
            return (0..<Int(buffer.frameLength)).map { Float(data[$0]) / 32768 }
        }
        return []
    }
}

/// 音频线程与主线程共享的溢出标志。
final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value = false
        return current
    }
}
