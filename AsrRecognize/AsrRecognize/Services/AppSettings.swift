import Combine
import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let apiKey = "deepseek_api_key"
        static let language = "recognition_language"
        static let offline = "recognition_offline_only"
        static let autoSummary = "auto_summary"
    }

    @Published var apiKey: String {
        didSet { KeychainStore.save(apiKey, for: Keys.apiKey) }
    }

    @Published var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Keys.language) }
    }

    @Published var offlineOnly: Bool {
        didSet { defaults.set(offlineOnly, forKey: Keys.offline) }
    }

    @Published var autoSummarize: Bool {
        didSet { defaults.set(autoSummarize, forKey: Keys.autoSummary) }
    }

    let model = "deepseek-chat"

    private let defaults = UserDefaults.standard

    init() {
        apiKey = KeychainStore.read(Keys.apiKey)
        languageCode = defaults.string(forKey: Keys.language) ?? "zh-CN"
        offlineOnly = defaults.bool(forKey: Keys.offline)
        autoSummarize = defaults.object(forKey: Keys.autoSummary) as? Bool ?? true
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var languageTitle: String {
        languageCode == "en-US" ? "English" : "中文"
    }
}
