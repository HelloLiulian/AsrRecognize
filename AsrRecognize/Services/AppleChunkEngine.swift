import AVFoundation
import Foundation
import Speech

final class AppleChunkEngine: ChunkTranscriptionEngine, @unchecked Sendable {
    let displayName = "System-Spracherkennung"

    private let localeIdentifier: String
    private let offlineOnly: Bool
    private var recognizer: SFSpeechRecognizer?

    init(localeIdentifier: String, offlineOnly: Bool) {
        self.localeIdentifier = localeIdentifier
        self.offlineOnly = offlineOnly
    }

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let authorized = await Self.requestAuthorization()
        guard authorized else { throw TranscriptionEngineError.permissionDenied }

        progress(0.5, "Spracherkennung wird vorbereitet…")
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw TranscriptionEngineError.unsupportedLanguage
        }
        if offlineOnly && !recognizer.supportsOnDeviceRecognition {
            throw TranscriptionEngineError.offlineUnavailable
        }
        self.recognizer = recognizer
        progress(1, "")
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let recognizer else { throw TranscriptionEngineError.notPrepared }
        guard recognizer.isAvailable || offlineOnly else {
            throw TranscriptionEngineError.serviceUnavailable
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw TranscriptionEngineError.emptyResult
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let destination = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                destination.update(from: base, count: samples.count)
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = offlineOnly
        request.addsPunctuation = true
        request.append(buffer)
        request.endAudio()

        let box = RecognitionBox()
        let text = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    let guardOnce = ContinuationGuard()
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error {
                            guard guardOnce.claim() else { return }
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let result, result.isFinal, guardOnce.claim() else { return }
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                    box.set(task)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw TranscriptionEngineError.timeout
            }
            defer {
                group.cancelAll()
                box.cancel()
            }
            guard let value = try await group.next() else {
                throw TranscriptionEngineError.emptyResult
            }
            return value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionEngineError.emptyResult }
        return trimmed
    }

    func unload() async {
        recognizer = nil
    }

    private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

private final class ContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func set(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}
