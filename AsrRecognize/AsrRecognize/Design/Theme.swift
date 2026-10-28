import SwiftUI

enum Theme {
    static let background = Color(hex: 0x06070A)
    static let surface = Color(hex: 0x0C0E13)
    static let elevated = Color(hex: 0x14171F)
    static let cardFill = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.16)

    static let textPrimary = Color(hex: 0xF4F6FA)
    static let textSecondary = Color(hex: 0x9AA3B5)
    static let textTertiary = Color(hex: 0x616A7C)

    static let accent = Color(hex: 0x4D8DFF)
    static let accentBright = Color(hex: 0x7CC4FF)
    static let cyan = Color(hex: 0x53E8FF)
    static let violet = Color(hex: 0x8C6BFF)
    static let record = Color(hex: 0xFF453A)
    static let recordDeep = Color(hex: 0xFF7A45)
    static let success = Color(hex: 0x32D74B)
    static let warning = Color(hex: 0xFFD60A)

    static let accentGradient = LinearGradient(
        colors: [accent, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let recordGradient = LinearGradient(
        colors: [recordDeep, record],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
