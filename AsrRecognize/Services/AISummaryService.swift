import Foundation

enum AISummaryService {
    static func summarize(
        transcript: String,
        configuration: AIConfiguration,
        session: URLSession = .shared
    ) async throws -> MeetingSummary {
        let request = try AISummaryRequest.make(configuration: configuration, transcript: transcript)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as AISummaryError {
            throw error
        } catch {
            throw AISummaryError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw AISummaryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw AISummaryError.server(envelope.error.message)
            }
            throw AISummaryError.server("Die KI-Anfrage ist fehlgeschlagen (HTTP \(http.statusCode)).")
        }

        let envelope: ChatEnvelope
        do {
            envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        } catch {
            throw AISummaryError.invalidResponse
        }
        guard let content = envelope.choices.first?.message.content, !content.isEmpty else {
            throw AISummaryError.invalidResponse
        }
        return try AISummaryRequest.parse(content: content)
    }

    private struct ChatEnvelope: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String? }
    }

    private struct APIErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable { let message: String }
    }
}
