import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationSummarizer {
    static var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
#endif
        return false
    }

    static var availabilityMessage: String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Die lokale KI ist verfügbar."
            case .unavailable(.deviceNotEligible):
                return "Dieses Gerät unterstützt Apple Intelligence nicht."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence ist nicht aktiviert. Bitte in den iOS-Einstellungen einschalten."
            case .unavailable(.modelNotReady):
                return "Das lokale Modell wird noch vorbereitet. Bitte später erneut versuchen."
            case .unavailable:
                return "Die lokale KI ist derzeit nicht verfügbar."
            }
        }
        return "Für die lokale KI ist iOS 26 oder neuer erforderlich."
#else
        return "Diese App-Version wurde ohne iOS-26-Unterstützung gebaut."
#endif
    }

    static func summarize(transcript: String) async throws -> MeetingSummary {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await summarizeOnDevice(transcript: transcript)
        }
#endif
        throw AISummaryError.onDeviceUnavailable(availabilityMessage)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func summarizeOnDevice(transcript: String) async throws -> MeetingSummary {
        guard isAvailable else {
            throw AISummaryError.onDeviceUnavailable(availabilityMessage)
        }

        let (chunks, _) = OnDeviceTranscriptChunker.chunks(for: transcript)
        guard !chunks.isEmpty else { throw AISummaryError.invalidResponse }

        guard chunks.count > 1 else {
            return try await requestSummary(from: chunks[0])
        }

        var notes: [String] = []
        for chunk in chunks {
            let session = LanguageModelSession(instructions: Self.noteInstructions)
            do {
                let response = try await session.respond(to: "Abschnitt:\n\(chunk)")
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    notes.append(trimmed)
                }
            } catch {
                throw AISummaryError.onDeviceFailed
            }
        }

        guard !notes.isEmpty else { throw AISummaryError.onDeviceFailed }
        let merged = notes.joined(separator: "\n\n")
        return try await requestSummary(from: String(merged.prefix(6_000)))
    }

    @available(iOS 26.0, *)
    private static func requestSummary(from source: String) async throws -> MeetingSummary {
        let session = LanguageModelSession(instructions: AISummaryRequest.systemPrompt)
        do {
            let response = try await session.respond(to: "Transkript der Besprechung:\n\(source)")
            return try AISummaryRequest.parse(content: response.content)
        } catch let error as AISummaryError {
            throw error
        } catch {
            throw AISummaryError.onDeviceFailed
        }
    }

    private static let noteInstructions = """
    Sie erstellen Notizen aus einem Abschnitt eines Besprechungstranskripts. Antworten Sie auf Deutsch und ausschließlich mit kurzen Stichpunkten zu Kernaussagen, Aufgaben (mit Verantwortlichem und Frist, falls genannt) und Beschlüssen. Keine Einleitung, keine Wiederholung.
    """
#endif
}
