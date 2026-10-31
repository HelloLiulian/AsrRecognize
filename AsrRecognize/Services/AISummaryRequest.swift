import Foundation

struct AIConfiguration: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

enum AISummaryError: LocalizedError {
    case invalidURL
    case missingKey
    case invalidResponse
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die Basis-URL ist ungültig. Bitte eine https://-Adresse eingeben."
        case .missingKey:
            return "Es ist kein API-Schlüssel hinterlegt."
        case .invalidResponse:
            return "Die Antwort der KI konnte nicht verarbeitet werden."
        case .network:
            return "Die Verbindung zum KI-Anbieter ist fehlgeschlagen. Bitte prüfen Sie Ihre Internetverbindung."
        case .server(let message):
            return message
        }
    }
}

enum AISummaryRequest {
    static let maxCharacters = 120_000

    static let systemPrompt = """
    Sie sind ein erfahrener Protokollassistent. Erstellen Sie aus dem bereitgestellten Transkript ein strukturiertes Besprechungsprotokoll.
    Geben Sie ausschließlich JSON aus, ohne Markdown-Codeblöcke oder Erklärungen. Struktur:
    {"overview":"Zusammenfassung in 100 bis 200 Wörtern","keyPoints":["Kernpunkt"],"actionItems":[{"task":"Aufgabe","owner":"Verantwortlich oder leer","deadline":"Frist oder leer"}],"decisions":["Beschluss"]}
    Anforderungen:
    1. Verwenden Sie ausschließlich Informationen aus dem Transkript. Erfinden Sie keine Fakten, Namen oder Zahlen.
    2. Antworten Sie vollständig auf Deutsch.
    3. Aufgaben müssen konkret und umsetzbar sein, maximal 8.
    4. Wenn eine Kategorie im Transkript fehlt, geben Sie ein leeres Array zurück.
    """

    static func normalizedBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func endpointURL(_ raw: String) throws -> URL {
        let base = normalizedBaseURL(raw)
        guard let components = URLComponents(string: base),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            throw AISummaryError.invalidURL
        }
        guard let url = URL(string: base + "/chat/completions") else {
            throw AISummaryError.invalidURL
        }
        return url
    }

    static func trimmedTranscript(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > maxCharacters else { return (text, false) }
        return (String(text.prefix(maxCharacters)), true)
    }

    static func make(configuration: AIConfiguration, transcript: String) throws -> URLRequest {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AISummaryError.missingKey }

        let url = try endpointURL(configuration.baseURL)
        let source = trimmedTranscript(transcript).text

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Transkript der Besprechung:\n\(source)"]
            ],
            "temperature": 0.2,
            "max_tokens": 2000,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(content: String) throws -> MeetingSummary {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end {
            cleaned = String(cleaned[start...end])
        }
        if let data = cleaned.data(using: .utf8),
           let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data),
           !summary.isEmpty {
            return summary
        }
        let fallback = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { throw AISummaryError.invalidResponse }
        return MeetingSummary(overview: fallback)
    }
}
