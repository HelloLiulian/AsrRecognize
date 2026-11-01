import Foundation

enum RecognitionLanguage {
    static func qwenHint(for code: String) -> String {
        code.hasPrefix("en") ? "english" : "german"
    }

    static func appleLocale(for code: String) -> String {
        code.hasPrefix("en") ? "en-US" : "de-DE"
    }

    static func title(for code: String) -> String {
        code.hasPrefix("en") ? "English" : "Deutsch"
    }
}
