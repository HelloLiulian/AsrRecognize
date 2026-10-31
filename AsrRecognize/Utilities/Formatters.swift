import Foundation

enum AppFormat {
    static let locale = Locale(identifier: "de_DE")

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = locale
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    static let meetingDate = makeFormatter("dd.MM.yyyy, HH:mm")
    static let dayOnly = makeFormatter("dd.MM.yyyy")
    static let heroDate = makeFormatter("EEEE, d. MMMM")
    static let fileStamp = makeFormatter("yyyy-MM-dd")

    static func clock(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func duration(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        if total < 60 {
            return "\(total) Sek."
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0, minutes > 0 {
            return "\(hours) Std. \(minutes) Min."
        }
        if hours > 0 {
            return "\(hours) Std."
        }
        return "\(minutes) Min."
    }

    private static let characterFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func characterCount(_ count: Int) -> String {
        let number = characterFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(number) Zeichen"
    }

    static func weekLabel(_ date: Date) -> String {
        "KW \(calendar.component(.weekOfYear, from: date))"
    }

    static func defaultTitle(for date: Date) -> String {
        "Protokoll vom \(dayOnly.string(from: date))"
    }
}
