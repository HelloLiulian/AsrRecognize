import Foundation

enum TranscriptionEngineError: LocalizedError {
    case notPrepared
    case modelMissing
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "本地识别模型尚未准备好"
        case .modelMissing:
            return "App 包内没有 Qwen3ASR 模型文件"
        case .emptyResult:
            return "本地识别没有返回文字"
        }
    }
}

/// 单段音频 -> 文本。会议场景由 VAD 切段后调用，不要求流式。
protocol ChunkTranscriptionEngine: AnyObject, Sendable {
    var displayName: String { get }
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws
    func transcribe(samples: [Float], language: String?) async throws -> String
    func unload() async
}

/// 检查 App 包内是否打进完整模型（CI 构建带模型时才有）。
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
