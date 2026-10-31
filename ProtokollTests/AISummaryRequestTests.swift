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
        let systemContent = try XCTUnwrap(messages[0]["content"])
        let userContent = try XCTUnwrap(messages[1]["content"])
        XCTAssertTrue(systemContent.contains("Protokollassistent"))
        XCTAssertTrue(systemContent.contains("Deutsch"))
        XCTAssertTrue(userContent.contains("Hallo zusammen."))
    }

    func testTranscriptTruncation() throws {
        let long = String(repeating: "a", count: AISummaryRequest.maxCharacters + 10)
        let (text, truncated) = AISummaryRequest.trimmedTranscript(long)
        XCTAssertTrue(truncated)
        XCTAssertEqual(text.count, AISummaryRequest.maxCharacters)
    }

    func testTranscriptTruncationBoundary() throws {
        let exact = String(repeating: "b", count: AISummaryRequest.maxCharacters)
        let (exactText, exactTruncated) = AISummaryRequest.trimmedTranscript(exact)
        XCTAssertFalse(exactTruncated)
        XCTAssertEqual(exactText.count, AISummaryRequest.maxCharacters)

        let overByOne = String(repeating: "c", count: AISummaryRequest.maxCharacters + 1)
        let (overText, overTruncated) = AISummaryRequest.trimmedTranscript(overByOne)
        XCTAssertTrue(overTruncated)
        XCTAssertEqual(overText.count, AISummaryRequest.maxCharacters)
    }

    func testMissingKeyThrows() {
        for key in ["", "   \n\t"] {
            let config = AIConfiguration(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", apiKey: key)
            XCTAssertThrowsError(try AISummaryRequest.make(configuration: config, transcript: "Hallo")) { error in
                guard let aiError = error as? AISummaryError, case .missingKey = aiError else {
                    return XCTFail("Expected missingKey, got \(error)")
                }
            }
        }
    }

    func testParseSummary() throws {
        let content = """
        {"overview":"Kurz","keyPoints":["A"],"actionItems":[{"task":"T","owner":"Max","deadline":"Freitag"}],"decisions":["D"]}
        """
        let summary = try AISummaryRequest.parse(content: content)
        XCTAssertEqual(summary.overview, "Kurz")
        XCTAssertEqual(summary.actionItems.first?.owner, "Max")
    }

    func testParseFencedJSON() throws {
        let content = """
        ```json
        {"overview":"Aus Zaun","keyPoints":["B"]}
        ```
        """
        let summary = try AISummaryRequest.parse(content: content)
        XCTAssertEqual(summary.overview, "Aus Zaun")
        XCTAssertEqual(summary.keyPoints, ["B"])
    }

    func testParseEmptyThrows() {
        XCTAssertThrowsError(try AISummaryRequest.parse(content: "")) { error in
            guard let aiError = error as? AISummaryError, case .invalidResponse = aiError else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testParseNonJSONFallsBack() throws {
        let text = "Das ist kein JSON, sondern eine freie Antwort."
        let summary = try AISummaryRequest.parse(content: text)
        XCTAssertEqual(summary.overview, text)
        XCTAssertTrue(summary.keyPoints.isEmpty)
    }
}
