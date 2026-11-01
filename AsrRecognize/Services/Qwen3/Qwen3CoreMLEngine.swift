import CoreML
import Foundation
import Qwen3ASR
import os

/// Pure CoreML Qwen3-ASR engine: the model loads offline from the app bundle; recognition does not go through MLX/Metal.
actor Qwen3CoreMLEngine: ChunkTranscriptionEngine {
    nonisolated let displayName = "Lokales Qwen3-ASR (Core ML)"

    private static let logger = Logger(subsystem: "com.liulian.AsrRecognize", category: "Qwen3CoreML")

    /// Some devices fail to build the ANE execution plan for the palettized
    /// decoder (`error code: -14`), and GPU warm-up can stall indefinitely on
    /// iPadOS 26. Try full ANE first, then keep the encoder on ANE with a CPU
    /// decoder, and finally fall back to full CPU.
    private struct ComputePlan: Sendable {
        let name: String
        let encoder: MLComputeUnits
        let decoder: MLComputeUnits
    }

    private static let computePlans: [ComputePlan] = [
        .init(name: "ANE", encoder: .cpuAndNeuralEngine, decoder: .cpuAndNeuralEngine),
        .init(name: "ANE+CPU", encoder: .cpuAndNeuralEngine, decoder: .cpuOnly),
        .init(name: "CPU", encoder: .cpuOnly, decoder: .cpuOnly),
    ]

    private var model: CoreMLASRModel?

    private static func verboseLog(_ message: String, _ plan: ComputePlan, _ started: CFAbsoluteTime) {
        let milliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        logger.info("\(message, privacy: .public) \(plan.name, privacy: .public) plan in \(milliseconds, privacy: .public) ms")
    }

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard model == nil else { return }
        guard LocalModelAssets.isBundled, let directory = LocalModelAssets.directory else {
            throw TranscriptionEngineError.modelMissing
        }

        var lastError: Error?
        let planSpan = 0.86 / Double(Self.computePlans.count)
        for (index, plan) in Self.computePlans.enumerated() {
            try Task.checkCancellation()
            let base = 0.02 + planSpan * Double(index)
            let label = "(\(index + 1)/\(Self.computePlans.count), \(plan.name))"
            let started = CFAbsoluteTimeGetCurrent()
            do {
                progress(base, "Lokales Modell wird geladen \(label)…")
                let loaded = try await CoreMLASRModel.fromPretrained(
                    encoderComputeUnits: plan.encoder,
                    decoderComputeUnits: plan.decoder,
                    cacheDir: directory,
                    offlineMode: true
                ) { fraction, _ in
                    progress(base + fraction * planSpan, "Lokales Modell wird geladen \(label)…")
                }
                Self.verboseLog("Qwen3 models loaded with", plan, started)

                try Task.checkCancellation()
                progress(base + planSpan, "Encoder wird geprüft \(label)…")
                try loaded.encoder.warmUp()
                Self.verboseLog("Qwen3 encoder warm-up ok with", plan, started)
                try Task.checkCancellation()
                progress(base + planSpan, "Decoder wird geprüft \(label)…")
                try loaded.decoder.warmUp()
                Self.verboseLog("Qwen3 decoder warm-up ok with", plan, started)
                try Task.checkCancellation()
                model = loaded
                Self.logger.info("Qwen3 model ready with \(plan.name, privacy: .public) compute plan")
                progress(1.0, "Modell bereit")
                return
            } catch is CancellationError where Task.isCancelled {
                Self.logger.info("Qwen3 model load cancelled on \(plan.name, privacy: .public)")
                throw CancellationError()
            } catch {
                lastError = error
                Self.logger.error("Qwen3 load failed on \(plan.name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        Self.logger.error("Qwen3 model unavailable after all compute plans: \(String(describing: lastError), privacy: .public)")
        throw TranscriptionEngineError.modelLoadFailed
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let model else { throw TranscriptionEngineError.notPrepared }
        let text = try model.transcribeWithoutMLX(
            audio: samples,
            sampleRate: 16_000,
            language: language,
            maxTokens: 448
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionEngineError.emptyResult }
        return trimmed
    }

    func unload() {
        model = nil
    }
}
