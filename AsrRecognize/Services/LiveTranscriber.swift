import AVFoundation
import Combine
import Foundation
import Speech

enum TranscriberError: LocalizedError {
    case noInput

    var errorDescription: String? {
        "Kein Mikrofoneingang gefunden."
    }
}

final class LiveTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var partialText = ""
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var startDate: Date?
    @Published private(set) var audioFileName: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var audioURL: URL?
    private var tapInstalled = false
    private var usesOfflineRecognition = false
    private var isStarting = false

    private var timer: Timer?
    private var rotationTimer: Timer?
    private var accumulated: TimeInterval = 0
    private var sessionStartedAt: Date?
    private var activeCycle = UUID()
    private var restartFailures = 0

    private var interruptionObserver: NSObjectProtocol?
    private var wasInterrupted = false

    deinit {
        timer?.invalidate()
        rotationTimer?.invalidate()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // MARK: - Public

    @MainActor
    func start(language: String, offlineOnly: Bool) async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil

        let speechGranted = await Self.requestSpeechAuthorization()
        guard !Task.isCancelled else { return }
        guard speechGranted else {
            errorMessage = "Kein Zugriff auf die Spracherkennung. Bitte in den iOS-Einstellungen unter „Datenschutz & Sicherheit › Spracherkennung“ aktivieren."
            return
        }

        let micGranted = await Self.requestMicrophonePermission()
        guard !Task.isCancelled else { return }
        guard micGranted else {
            errorMessage = "Kein Zugriff auf das Mikrofon. Bitte in den iOS-Einstellungen unter „Datenschutz & Sicherheit › Mikrofon“ aktivieren."
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            errorMessage = "Für diese Sprache ist keine Spracherkennung verfügbar."
            return
        }

        let wantsOffline = offlineOnly && recognizer.supportsOnDeviceRecognition
        guard recognizer.isAvailable || wantsOffline else {
            errorMessage = "Die Spracherkennung ist derzeit nicht verfügbar. Bitte prüfen Sie Ihre Internetverbindung."
            return
        }

        let isRetry = startDate != nil
        self.recognizer = recognizer
        usesOfflineRecognition = wantsOffline
        beginSession(isRetry: isRetry)
    }

    private func beginSession(isRetry: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw TranscriberError.noInput
            }

            let url = AudioStorage.makeNewFileURL()
            let file = try AVAudioFile(forWriting: url, settings: format.settings)

            if isRetry, let previousURL = audioURL {
                try? FileManager.default.removeItem(at: previousURL)
            }

            audioFile = file
            audioURL = url
            audioFileName = url.lastPathComponent

            partialText = ""
            level = 0
            if isRetry {
                startDate = startDate ?? Date()
            } else {
                segments = []
                elapsed = 0
                accumulated = 0
                startDate = Date()
            }
            restartFailures = 0
            wasInterrupted = false

            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self, self.isRecording else { return }
                self.recognitionRequest?.append(buffer)
                try? self.audioFile?.write(from: buffer)
                self.captureLevel(from: buffer)
            }
            tapInstalled = true

            isRecording = true
            isPaused = false
            sessionStartedAt = Date()

            startRecognitionCycle()

            engine.prepare()
            try engine.start()

            installInterruptionObserver()
            startTimers()
        } catch {
            cleanupAfterFailure()
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }

        if let sessionStartedAt {
            accumulated += Date().timeIntervalSince(sessionStartedAt)
        }
        sessionStartedAt = nil
        elapsed = accumulated
        isPaused = true

        engine.pause()
        finalizePartial()
        invalidateCurrentCycle()
        level = 0
    }

    func resume() {
        guard isRecording, isPaused else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isPaused = false
            sessionStartedAt = Date()
            restartFailures = 0
            wasInterrupted = false
            startRecognitionCycle()
        } catch {
            errorMessage = "Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording else { return }

        if !isPaused, let sessionStartedAt {
            accumulated += Date().timeIntervalSince(sessionStartedAt)
        }
        sessionStartedAt = nil
        elapsed = accumulated
        isRecording = false
        isPaused = false

        timer?.invalidate()
        timer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil

        finalizePartial()
        invalidateCurrentCycle()

        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        audioFile = nil
        level = 0
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discard() {
        if isRecording {
            stop()
        }
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

    // MARK: - Recognition cycle

    private func startRecognitionCycle() {
        guard isRecording, !isPaused, let recognizer, recognizer.isAvailable else { return }

        invalidateCurrentCycle()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = usesOfflineRecognition
        recognitionRequest = request

        let cycle = UUID()
        activeCycle = cycle

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isRecording, self.activeCycle == cycle else { return }

                if let result {
                    if result.isFinal {
                        self.restartFailures = 0
                        self.commitPartial(text: result.bestTranscription.formattedString)
                        if self.isRecording, !self.isPaused {
                            self.startRecognitionCycle()
                        }
                    } else {
                        self.restartFailures = 0
                        self.partialText = result.bestTranscription.formattedString
                    }
                }

                if let error, self.activeCycle == cycle, self.isRecording, !self.isPaused {
                    self.handleRecognitionFailure(error)
                }
            }
        }
    }

    private func invalidateCurrentCycle() {
        activeCycle = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func commitPartial(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        guard !trimmed.isEmpty else { return }
        segments.append(TranscriptSegment(text: trimmed, timestamp: elapsed))
    }

    private func finalizePartial() {
        let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        guard !trimmed.isEmpty else { return }
        segments.append(TranscriptSegment(text: trimmed, timestamp: elapsed))
    }

    private func rotateCycle() {
        guard isRecording, !isPaused else { return }
        finalizePartial()
        startRecognitionCycle()
    }

    private func handleRecognitionFailure(_ error: Error) {
        guard isRecording, !isPaused else { return }

        finalizePartial()
        restartFailures += 1

        let nsError = error as NSError
        let benignCodes = [203, 216, 1101, 1110]
        let isBenign = nsError.domain == "kAFAssistantErrorDomain" && benignCodes.contains(nsError.code)
        let limit = isBenign ? 8 : 2

        if restartFailures > limit {
            errorMessage = "Spracherkennung unterbrochen: \(error.localizedDescription)"
            stop()
            return
        }

        let delay = min(0.4 * Double(restartFailures), 2.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRecording, !self.isPaused else { return }
            self.startRecognitionCycle()
        }
    }

    // MARK: - Audio

    private func captureLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for index in 0..<frames {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frames))
        let decibels = 20 * log10(max(rms, 0.00001))
        let normalized = max(0, min(1, (decibels + 55) / 55))

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording, !self.isPaused else { return }
            self.level = self.level * 0.62 + CGFloat(normalized) * 0.38
        }
    }

    private func startTimers() {
        timer?.invalidate()
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateElapsed()
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick

        rotationTimer?.invalidate()
        let rotate = Timer(timeInterval: 50, repeats: true) { [weak self] _ in
            self?.rotateCycle()
        }
        RunLoop.main.add(rotate, forMode: .common)
        rotationTimer = rotate
    }

    private func updateElapsed() {
        guard isRecording, !isPaused, let sessionStartedAt else { return }
        elapsed = accumulated + Date().timeIntervalSince(sessionStartedAt)
    }

    private func cleanupAfterFailure() {
        isRecording = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil

        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        invalidateCurrentCycle()
        audioFile = nil
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
        audioFileName = nil
        sessionStartedAt = nil
        level = 0
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Interruptions

    private func installInterruptionObserver() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            guard isRecording, !isPaused else { return }
            wasInterrupted = true
            pause()
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard wasInterrupted, isRecording, isPaused, options.contains(.shouldResume) else { return }
            wasInterrupted = false
            resume()
        @unknown default:
            break
        }
    }

    // MARK: - Permissions

    private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
