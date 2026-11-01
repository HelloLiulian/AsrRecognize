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

        let box = RecognitionBox()
        let text = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        guard box.install(continuation) else { return }
                        let task = recognizer.recognitionTask(with: request) { result, error in
                            if let error {
                                box.fail(error)
                                return
                            }
                            guard let result, result.isFinal else { return }
                            box.succeed(result.bestTranscription.formattedString)
                        }
                        box.attach(task)
                        request.append(buffer)
                        request.endAudio()
                    }
                } onCancel: {
                    box.cancel()
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

private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private var cancelled = false
    private var finished = false

    @discardableResult
    func install(_ continuation: CheckedContinuation<String, Error>) -> Bool {
        lock.lock()
        if cancelled || finished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func attach(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled || finished
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func succeed(_ text: String) {
        finish(.success(text))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let continuation = self.continuation
        let task = self.task
        self.continuation = nil
        self.task = nil
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        task?.cancel()
        if !alreadyFinished {
            continuation?.resume(throwing: CancellationError())
        }
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        self.task = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
