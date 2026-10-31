import XCTest
@testable import ProtokollLogic

final class ExportServiceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    func testSanitizeKeepsUmlautsAndRemovesIllegalCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("Besprechung: Q4/Plan? äöü"), "Besprechung- Q4-Plan- äöü")
        XCTAssertEqual(FilenameSanitizer.sanitize("   ...   "), "Protokoll")
        XCTAssertEqual(FilenameSanitizer.sanitize(String(repeating: "a", count: 80)).count, 60)
    }

    func testSanitizeLimitsLongEmojiTitleByUTF8Bytes() {
        let sanitized = FilenameSanitizer.sanitize(String(repeating: "🎉🚀", count: 40))
        XCTAssertLessThanOrEqual(sanitized.utf8.count, 180)
        XCTAssertLessThanOrEqual(sanitized.count, 60)
        XCTAssertFalse(sanitized.isEmpty)
    }

    func testSanitizeLimitsLongCJKTitleByUTF8Bytes() {
        let sanitized = FilenameSanitizer.sanitize(String(repeating: "架构决策会议", count: 20))
        XCTAssertLessThanOrEqual(sanitized.utf8.count, 180)
        XCTAssertFalse(sanitized.isEmpty)
    }

    func testGeneratedFilenameStaysBelowAPFSByteLimit() throws {
        let payload = ExportPayload(
            title: String(repeating: "🎉🚀", count: 40) + " sehr langes Meeting über Architektur Entscheidungen",
            date: date,
            duration: 60,
            transcript: "Text.",
            summary: nil
        )
        let url = try ExportService.writeText(for: payload)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Protokoll_"))
        XCTAssertLessThanOrEqual(url.lastPathComponent.utf8.count, 255)
    }

    func testEmptyTitleProducesSingleProtokollSegment() throws {
        let payload = ExportPayload(title: "   ", date: date, duration: 60, transcript: "Text.", summary: nil)
        let url = try ExportService.writeText(for: payload)
        XCTAssertEqual(url.lastPathComponent, "Protokoll_\(AppFormat.fileStamp.string(from: date)).txt")
    }

    func testTextWithoutSummary() {
        let payload = ExportPayload(
            title: "Teamrunde",
            date: date,
            duration: 3_900,
            transcript: "Guten Tag.",
            summary: nil
        )
        let text = ExportService.text(for: payload)
        XCTAssertTrue(text.contains("Datum:"))
        XCTAssertTrue(text.contains("Dauer: 1 Std. 5 Min."))
        XCTAssertTrue(text.contains("## Transkript\nGuten Tag."))
        XCTAssertFalse(text.contains("## Zusammenfassung"))
    }

    func testTextWithSummary() {
        let summary = MeetingSummary(
            overview: "Kurz",
            keyPoints: ["A", "B"],
            actionItems: [ActionItem(task: "Liefern", owner: "Max", deadline: "Freitag")],
            decisions: ["Freigabe erteilt"]
        )
        let payload = ExportPayload(title: "Planung", date: date, duration: 60, transcript: "Text.", summary: summary)
        let text = ExportService.text(for: payload)
        XCTAssertTrue(text.contains("## Zusammenfassung\nKurz"))
        XCTAssertTrue(text.contains("- Liefern · Verantwortlich: Max · Frist: Freitag"))
        XCTAssertTrue(text.contains("## Beschlüsse\n- Freigabe erteilt"))
    }
}
