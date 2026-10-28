import Foundation

enum AppFormat {
    static let zhLocale = Locale(identifier: "zh_CN")

    static let meetingDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = zhLocale
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = zhLocale
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let heroDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = zhLocale
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter
    }()

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
            return "\(total) 秒"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(minutes) 分钟"
    }

    static func defaultTitle(for date: Date) -> String {
        "\(dayOnly.string(from: date)) 会议"
    }
}
