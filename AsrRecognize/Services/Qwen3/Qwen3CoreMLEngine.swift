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
        .init(name: "ANE", encoder: .cpuAndNeuralEngine, decoder: .cpuAndNeuralEngine),
        .init(name: "GPU", encoder: .all, decoder: .cpuAndGPU),
        .init(name: "CPU", encoder: .cpuOnly, decoder: .cpuOnly),
    ]

    private var model: CoreMLASRModel?

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard model == nil else { return }
        guard LocalModelAssets.isBundled, let directory = LocalModelAssets.directory else {
            throw TranscriptionEngineError.modelMissing
        }

        var lastError: Error?
        for (index, plan) in Self.computePlans.enumerated() {
            do {
                progress(0.02, index == 0 ? "Lokales Modell wird gelesen…" : "Lokales Modell wird erneut geladen…")
                let loaded = try await CoreMLASRModel.fromPretrained(
                    encoderComputeUnits: plan.encoder,
                    decoderComputeUnits: plan.decoder,
                    cacheDir: directory,
                    offlineMode: true
                ) { fraction, _ in
                    progress(0.02 + fraction * 0.86, "Lokales Modell wird geladen…")
                }

                progress(0.9, "Modell wird vorbereitet…")
                try loaded.warmUp()
                model = loaded
                Self.logger.info("Qwen3 model ready with \(plan.name, privacy: .public) compute plan")
                progress(1.0, "Modell bereit")
                return
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
