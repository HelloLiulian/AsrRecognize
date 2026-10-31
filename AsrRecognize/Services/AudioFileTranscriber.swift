import AVFoundation
import Combine
import Foundation

enum AudioFileTranscriberError: LocalizedError {
    case unreadable
    case noAudio

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Die Audiodatei konnte nicht gelesen werden."
        case .noAudio:
            return "Die Audiodatei enthält keine Tonspur."
        }
    }
}

@MainActor
final class AudioFileTranscriber: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, transcribing, paused, finished, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var processedTime: TimeInterval = 0
    @Published private(set) var estimatedRemaining: TimeInterval?
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var statusText = ""
    @Published private(set) var loadFraction: Double = 0
    @Published private(set) var errorMessage: String?

    private var job: ImportJob?
    private var audioURL: URL?
    private var engine: ChunkTranscriptionEngine?
    private var worker: Task<Void, Never>?
    private var pauseRequested = false
    private var cancelRequested = false
    private var startedAt: Date?
    private var generation = 0
    private let store = ImportJobStore.shared
    private let converter = Audio16kConverter()

    var framesProcessed: Int64 { job?.framesProcessed ?? 0 }

    func start(job: ImportJob, audioURL: URL, engine: ChunkTranscriptionEngine, resume: Bool) {
        self.job = job
        self.audioURL = audioURL
        self.engine = engine
        worker?.cancel()
        pauseRequested = false
        cancelRequested = false
        errorMessage = nil
        estimatedRemaining = nil
        startedAt = nil
        progress = 0
        processedTime = 0
        loadFraction = 0
        totalDuration = job.duration
        generation += 1
        let expected = generation
        worker = Task { [weak self] in
            await self?.run(generation: expected, resume: resume)
        }
    }

    func pause() {
        guard phase == .transcribing else { return }
        pauseRequested = true
        statusText = "Wird pausiert…"
    }

    func resume() {
        guard (phase == .paused || phase == .failed), let job, let audioURL, let engine else { return }
        start(job: job, audioURL: audioURL, engine: engine, resume: true)
    }

    func cancel() {
        cancelRequested = true
        worker?.cancel()
    }

    private func run(generation expected: Int, resume: Bool) async {
        guard var job, let audioURL, let engine, generation == expected else { return }
        defer {
            if generation == expected { worker = nil }
        }
        phase = .preparing
        statusText = "Audio wird vorbereitet…"

        do {
            try await engine.prepare { [weak self] fraction, message in
                Task { @MainActor in
                    guard let self else { return }
                    self.loadFraction = fraction
                    if !message.isEmpty { self.statusText = message }
                }
            }

            let file = try AVAudioFile(forReading: audioURL)
            let format = file.processingFormat
            let totalFrames = file.length
            guard totalFrames > 0, format.sampleRate > 0 else { throw AudioFileTranscriberError.unreadable }

            if resume {
                let existing = await store.segments(for: job.id)
                let resumeTime = Double(job.framesProcessed) / format.sampleRate
                segments = existing.filter { $0.timestamp < resumeTime }
                if segments.count != existing.count {
                    try await store.replaceSegments(segments, for: job.id)
                }
            } else {
                segments = []
                job.framesProcessed = 0
                job.sourceSampleRate = format.sampleRate
                try await store.update(job)
                try await store.replaceSegments([], for: job.id)
            }

            file.framePosition = AVAudioFramePosition(job.framesProcessed)
            var framesRead = Int64(job.framesProcessed)
            let capacity: AVAudioFrameCount = 16_384
            let vad = VoiceActivityDetector()

            job.status = .running
            try await store.update(job)
            phase = .transcribing
            statusText = ""
            startedAt = Date()

            while framesRead < totalFrames {
                if generation != expected { return }
                if cancelRequested { throw CancellationError() }
                if pauseRequested {
                    job.framesProcessed = framesRead
                    job.status = .paused
                    try await store.update(job)
                    self.job = job
                    pauseRequested = false
                    estimatedRemaining = nil
                    phase = .paused
                    statusText = ""
                    return
                }
                if attemptMemoryThrottle(audioURL: audioURL) {
                    await Task.yield()
                }

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                    throw AudioFileTranscriberError.unreadable
                }
                try file.read(into: buffer)
                if buffer.frameLength == 0 { break }

                let samples = converter.convert(buffer)
                let timestamp = Double(framesRead) / format.sampleRate
                let chunkStartFrames = framesRead
                let segmentStartIndex = segments.count
                do {
                    for segment in vad.feed(samples) {
                        try await recognize(
                            segment,
                            timestamp: timestamp,
                            engine: engine,
                            job: &job
                        )
                    }
                    framesRead += Int64(buffer.frameLength)
                    job.framesProcessed = framesRead
                    try await store.update(job)
                } catch {
                    if segments.count > segmentStartIndex {
                        segments.removeSubrange(segmentStartIndex...)
                        try? await store.replaceSegments(segments, for: job.id)
                    }
                    framesRead = chunkStartFrames
                    job.framesProcessed = chunkStartFrames
                    throw error
                }

                self.job = job
                progress = min(1, Double(framesRead) / Double(totalFrames))
                processedTime = job.duration * progress
                if let startedAt, progress > 0.02 {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    estimatedRemaining = max(0, elapsed * (1 - progress) / progress)
                }
            }

            if let tail = vad.flush() {
                try await recognize(
                    tail,
                    timestamp: Double(framesRead) / format.sampleRate,
                    engine: engine,
                    job: &job
                )
            }

            job.framesProcessed = totalFrames
            job.status = .finished
            try await store.update(job)
            self.job = job
            progress = 1
            processedTime = job.duration
            estimatedRemaining = nil
            statusText = "Transkription abgeschlossen"
            phase = .finished
        } catch is CancellationError {
            job.status = .paused
            try? await store.update(job)
            self.job = job
            estimatedRemaining = nil
            statusText = ""
            phase = .paused
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                errorMessage = description
            } else {
                errorMessage = "Die Transkription ist fehlgeschlagen. Bitte versuchen Sie es erneut."
            }
            if var current = self.job {
                current.status = .paused
                self.job = current
                try? await store.update(current)
            }
            phase = .failed
        }
    }

    private func recognize(
        _ samples: [Float],
        timestamp: TimeInterval,
        engine: ChunkTranscriptionEngine,
        job: inout ImportJob
    ) async throws {
        do {
            let text = try await transcribeWithRetry(
                samples,
                language: RecognitionLanguage.qwenHint(for: job.languageCode),
                engine: engine
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try Task.checkCancellation()
            let segment = TranscriptSegment(text: trimmed, timestamp: timestamp)
            segments.append(segment)
            try await store.append(segment, to: job.id)
        } catch TranscriptionEngineError.emptyResult {
            return
        }
    }

    private func transcribeWithRetry(
        _ samples: [Float],
        language: String,
        engine: ChunkTranscriptionEngine
    ) async throws -> String {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let text = try await engine.transcribe(samples: samples, language: language)
                try Task.checkCancellation()
                return text
            } catch TranscriptionEngineError.emptyResult {
                throw TranscriptionEngineError.emptyResult
            } catch TranscriptionEngineError.timeout {
                throw TranscriptionEngineError.timeout
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                if attempt > 2 { throw error }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func attemptMemoryThrottle(audioURL: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
        return size > 500_000_000
    }
}
