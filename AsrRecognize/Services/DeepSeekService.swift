import Foundation

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "尚未配置 DeepSeek API Key"
        case .invalidResponse:
            return "AI 返回的内容无法解析，请重试"
        case .server(let message):
            return message
        }
    }
}

enum DeepSeekService {
    static func summarize(transcript: String, apiKey: String) async throws -> MeetingSummary {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingKey }

        let source = String(transcript.prefix(20000))
        let systemPrompt = """
        你是一位资深会议纪要助理。请根据用户提供的会议转写文本，输出一份结构化纪要。
        只输出 JSON，不要输出 Markdown 代码块或任何解释。JSON 结构如下：
        {"overview":"100-200字的会议摘要","keyPoints":["关键要点"],"actionItems":[{"task":"待办事项","owner":"负责人，未知则为空字符串","deadline":"时间，未知则为空字符串"}],"decisions":["达成的决议"]}
        要求：
        1. 只依据原文，不要编造事实、人名或数字；
        2. 全部使用简体中文；
        3. 待办事项必须具体、可执行，最多 8 条；
        4. 若某一类信息原文没有，请返回空数组。
        """

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "会议转写原文：\n\(source)"]
            ],
            "temperature": 0.2,
            "max_tokens": 2000,
            "stream": false
        ]

        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw DeepSeekError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw DeepSeekError.server(envelope.error.message)
            }
            throw DeepSeekError.server("DeepSeek 请求失败（HTTP \(http.statusCode)）")
        }

        let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw DeepSeekError.invalidResponse
        }

        return try parse(content: content)
    }

    private static func parse(content: String) throws -> MeetingSummary {
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
        guard !fallback.isEmpty else { throw DeepSeekError.invalidResponse }
        return MeetingSummary(overview: fallback)
    }

    private struct ChatEnvelope: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }

    private struct APIErrorEnvelope: Decodable {
        let error: APIError

        struct APIError: Decodable {
            let message: String
        }
    }
}
