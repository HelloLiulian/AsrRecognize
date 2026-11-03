import XCTest
@testable import ProtokollLogic

final class AIProviderTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(AIProvider.mistral.defaultBaseURL, "https://api.eu.mistral.ai/v1")
        XCTAssertEqual(AIProvider.mistral.defaultModel, "mistral-large-latest")
        XCTAssertEqual(AIProvider.deepSeek.defaultBaseURL, "https://api.deepseek.com")
        XCTAssertEqual(AIProvider.deepSeek.defaultModel, "deepseek-chat")
        XCTAssertEqual(AIProvider.custom.defaultBaseURL, "https://api.openai.com/v1")
    }

    func testOnlyAppleSkipsAPIKey() {
        XCTAssertFalse(AIProvider.appleOnDevice.requiresAPIKey)
        for provider in [AIProvider.mistral, .deepSeek, .custom] {
            XCTAssertTrue(provider.requiresAPIKey, "\(provider) should require a key")
        }
    }

    func testDeepSeekHasEUPrivacyWarning() {
        XCTAssertNotNil(AIProvider.deepSeek.warning)
        XCTAssertTrue(AIProvider.deepSeek.warning?.contains("China") == true)
        XCTAssertNil(AIProvider.mistral.warning)
        XCTAssertNil(AIProvider.appleOnDevice.warning)
    }
}
