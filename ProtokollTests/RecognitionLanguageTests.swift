import XCTest
@testable import ProtokollLogic

final class RecognitionLanguageTests: XCTestCase {
    func testGermanMapping() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "de-DE"), "german")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "de-DE"), "de-DE")
    }

    func testEnglishMapping() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "en-US"), "english")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "en-US"), "en-US")
    }

    func testUnknownFallsBackToGerman() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "zh-CN"), "german")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "zh-CN"), "de-DE")
    }
}
