import XCTest
@testable import ProtokollLogic

final class AISummaryRequestTests: XCTestCase {
    private let configuration = AIConfiguration(
        baseURL: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        apiKey: "test-key"
    )

    func testEndpointNormalization() throws {
        let url = try AISummaryRequest.endpointURL("https://api.openai.com/v1/")
        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testRejectsNonHTTPS() {
        XCTAssertThrowsError(try AISummaryRequest.endpointURL("http://example.com"))
        XCTAssertThrowsError(try AISummaryRequest.endpointURL("not a url"))
    }

    func testRequestContainsGermanPromptAndModel() throws {
        let request = try AISummaryRequest.make(configuration: configuration, transcript: "Hallo zusammen.")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.timeoutInterval, 180)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]!.contains("Protokollassistent"))
        XCTAssertTrue(messages[0]["content"]!.contains("Deutsch"))
        XCTAssertTrue(messages[1]["content"]!.contains("Hallo zusammen."))
    }

    func testTranscriptTruncation() throws {
        let long = String(repeating: "a", count: AISummaryRequest.maxCharacters + 10)
        let (text, truncated) = AISummaryRequest.trimmedTranscript(long)
        XCTAssertTrue(truncated)
        XCTAssertEqual(text.count, AISummaryRequest.maxCharacters)
    }

    func testParseSummary() throws {
        let content = """
        {"overview":"Kurz","keyPoints":["A"],"actionItems":[{"task":"T","owner":"Max","deadline":"Freitag"}],"decisions":["D"]}
        """
        let summary = try AISummaryRequest.parse(content: content)
        XCTAssertEqual(summary.overview, "Kurz")
        XCTAssertEqual(summary.actionItems.first?.owner, "Max")
    }
}
