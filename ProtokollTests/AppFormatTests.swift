import XCTest
@testable import ProtokollLogic

final class AppFormatTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 14, _ min: Int = 30) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testMeetingDateIsGerman() {
        XCTAssertEqual(AppFormat.meetingDate.string(from: date(2026, 10, 31)), "31.10.2026, 14:30")
    }

    func testHeroDateIsGerman() {
        XCTAssertEqual(AppFormat.heroDate.string(from: date(2026, 10, 31)), "Samstag, 31. Oktober")
    }

    func testDurationGerman() {
        XCTAssertEqual(AppFormat.duration(45), "45 Sek.")
        XCTAssertEqual(AppFormat.duration(3_900), "1 Std. 5 Min.")
        XCTAssertEqual(AppFormat.duration(7_200), "2 Std.")
    }

    func testCharacterCountUsesGermanGrouping() {
        XCTAssertEqual(AppFormat.characterCount(1_234), "1.234 Zeichen")
        XCTAssertEqual(AppFormat.characterCount(0), "0 Zeichen")
    }

    func testWeekLabelIsISOWeek() {
        XCTAssertEqual(AppFormat.weekLabel(date(2026, 10, 31)), "KW 44")
    }

    func testDefaultTitle() {
        XCTAssertEqual(AppFormat.defaultTitle(for: date(2026, 10, 31)), "Protokoll vom 31.10.2026")
    }
}
