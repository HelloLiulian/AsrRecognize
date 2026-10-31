import Foundation

enum TranscriptionEngineError: LocalizedError {
    case notPrepared
    case modelMissing
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Das lokale Modell ist noch nicht bereit."
        case .modelMissing:
            return "Das lokale Qwen3-Modell ist in dieser App-Version nicht enthalten."
        case .emptyResult:
            return "Die lokale Erkennung hat keinen Text geliefert."
        }
    }
}

/// Single audio segment -> text. Called after VAD segmentation in meeting scenarios; streaming is not required.
protocol ChunkTranscriptionEngine: AnyObject, Sendable {
    var displayName: String { get }
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws
    func transcribe(samples: [Float], language: String?) async throws -> String
    func unload() async
}

/// Checks whether the full model is bundled in the app (only when the CI build includes the model).
enum LocalModelAssets {
    static var directory: URL? {
        Bundle.main.url(forResource: "Qwen3ASR", withExtension: nil)
    }

    static var isBundled: Bool {
        guard let directory else { return false }
        let required = [
            "encoder.mlmodelc",
            "embedding.mlmodelc",
            "decoder_part1.mlmodelc",
            "decoder_part2.mlmodelc",
            "vocab.json",
        ]
        return required.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
