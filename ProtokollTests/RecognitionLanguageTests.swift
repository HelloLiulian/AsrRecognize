import XCTest
@testable import ProtokollLogic

final class RecognitionLanguageTests: XCTestCase {
    func testGermanMapping() {
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "de-DE"), "de-DE")
        XCTAssertEqual(RecognitionLanguage.title(for: "de-DE"), "Deutsch")
    }

    func testEnglishMapping() {
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "en-US"), "en-US")
        XCTAssertEqual(RecognitionLanguage.title(for: "en-US"), "English")
    }

    func testUnknownFallsBackToGerman() {
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "zh-CN"), "de-DE")
        XCTAssertEqual(RecognitionLanguage.title(for: "zh-CN"), "Deutsch")
    }
}
