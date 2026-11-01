import CoreML
import Foundation
import Qwen3ASR
import os

/// Pure CoreML Qwen3-ASR engine: the model loads offline from the app bundle; recognition does not go through MLX/Metal.
actor Qwen3CoreMLEngine: ChunkTranscriptionEngine {
    nonisolated let displayName = "Lokales Qwen3-ASR (Core ML)"

    private static let logger = Logger(subsystem: "com.liulian.AsrRecognize", category: "Qwen3CoreML")

    /// Some devices fail to build the ANE execution plan for the palettized
    /// decoder (`error code: -14`). Retry the whole pipeline on GPU, then CPU,
    /// before reporting the model as unusable.
    private struct ComputePlan: Sendable {
        let name: String
        let encoder: MLComputeUnits
        let decoder: MLComputeUnits
    }

    private static let computePlans: [ComputePlan] = [
        .init(name: "Neuronale Engine", encoder: .cpuAndNeuralEngine, decoder: .cpuAndNeuralEngine),
        .init(name: "GPU", encoder: .cpuAndGPU, decoder: .cpuAndGPU),
        .init(name: "CPU", encoder: .cpuOnly, decoder: .cpuOnly),
    ]

    private var model: CoreMLASRModel?

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
            do {
                progress(base, "Lokales Modell wird geladen (\(index + 1)/\(Self.computePlans.count), \(plan.name))…")
                let loaded = try await CoreMLASRModel.fromPretrained(
                    encoderComputeUnits: plan.encoder,
                    decoderComputeUnits: plan.decoder,
                    cacheDir: directory,
                    offlineMode: true
                ) { fraction, _ in
                    progress(base + fraction * planSpan, "Lokales Modell wird geladen (\(index + 1)/\(Self.computePlans.count), \(plan.name))…")
                }

                try Task.checkCancellation()
                progress(base + planSpan, "Modell wird vorbereitet…")
                try loaded.warmUp()
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
