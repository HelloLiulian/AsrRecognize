import Foundation

enum TranscriptionEngineError: LocalizedError {
    case notPrepared
    case emptyResult
    case permissionDenied
    case unsupportedLanguage
    case offlineUnavailable
    case serviceUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Die Spracherkennung ist noch nicht bereit."
        case .emptyResult:
            return "Die Erkennung hat keinen Text geliefert."
        case .permissionDenied:
            return "Spracherkennung ist nicht erlaubt. Bitte in den iOS-Einstellungen aktivieren."
        case .unsupportedLanguage:
            return "Für diese Sprache ist keine Spracherkennung verfügbar."
        case .offlineUnavailable:
            return "Die Offline-Erkennung ist auf diesem Gerät für diese Sprache nicht verfügbar."
        case .serviceUnavailable:
            return "Die Spracherkennung ist derzeit nicht verfügbar. Bitte prüfen Sie die Internetverbindung."
        case .timeout:
            return "Die Spracherkennung hat zu lange nicht geantwortet."
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
