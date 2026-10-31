import CoreML
import Foundation
import Qwen3ASR

/// Pure CoreML Qwen3-ASR engine: the model loads offline from the app bundle; recognition does not go through MLX/Metal.
actor Qwen3CoreMLEngine: ChunkTranscriptionEngine {
    nonisolated let displayName = "Lokales Qwen3-ASR (Core ML)"

    private var model: CoreMLASRModel?

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard model == nil else { return }
        guard LocalModelAssets.isBundled, let directory = LocalModelAssets.directory else {
            throw TranscriptionEngineError.modelMissing
        }

        progress(0.02, "Lokales Modell wird gelesen…")
        let loaded = try await CoreMLASRModel.fromPretrained(
            encoderComputeUnits: .cpuAndNeuralEngine,
            decoderComputeUnits: .cpuAndNeuralEngine,
            cacheDir: directory,
            offlineMode: true
        ) { fraction, message in
            progress(0.02 + fraction * 0.88, message)
        }

        progress(0.92, "Modell wird vorbereitet…")
        try loaded.warmUp()
        model = loaded
        progress(1.0, "Modell bereit")
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
