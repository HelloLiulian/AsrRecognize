import Combine
import Foundation

enum ASREngine: String {
    case apple
    case qwen
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let apiKey = "deepseek_api_key"
        static let language = "recognition_language"
        static let offline = "recognition_offline_only"
        static let autoSummary = "auto_summary"
        static let engine = "recognition_engine"
        static let aiBaseURL = "ai_base_url"
        static let aiModel = "ai_model"
    }

    static let defaultBaseURL = "https://api.deepseek.com"
    static let defaultModel = "deepseek-flash"

    @Published var aiBaseURL: String {
        didSet {
            defaults.set(aiBaseURL, forKey: Keys.aiBaseURL)
            apiKey = KeychainStore.read(Self.keychainAccount(for: aiBaseURL))
        }
    }

    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }

    @Published var apiKey: String {
        didSet { KeychainStore.save(apiKey, for: Self.keychainAccount(for: aiBaseURL)) }
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

    @Published var engine: ASREngine {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    private let defaults = UserDefaults.standard

    init() {
        let savedLanguage = defaults.string(forKey: Keys.language)
        if let savedLanguage, savedLanguage != "zh-CN" {
            languageCode = savedLanguage
        } else {
            languageCode = "de-DE"
        }
        offlineOnly = defaults.bool(forKey: Keys.offline)
        autoSummarize = defaults.object(forKey: Keys.autoSummary) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.engine), let saved = ASREngine(rawValue: raw) {
            engine = saved
        } else {
            engine = LocalModelAssets.isBundled ? .qwen : .apple
        }

        let storedBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? Self.defaultBaseURL
        aiBaseURL = storedBaseURL
        aiModel = defaults.string(forKey: Keys.aiModel) ?? Self.defaultModel

        let account = Self.keychainAccount(for: storedBaseURL)
        let legacyKey = KeychainStore.read(Keys.apiKey)
        if !legacyKey.isEmpty {
            if KeychainStore.read(account).isEmpty {
                KeychainStore.save(legacyKey, for: account)
            }
            KeychainStore.delete(Keys.apiKey)
        }
        apiKey = KeychainStore.read(account)
    }

    static func keychainAccount(for baseURL: String) -> String {
        "ai-key:" + AISummaryRequest.normalizedBaseURL(baseURL)
    }

    var aiConfiguration: AIConfiguration {
        AIConfiguration(baseURL: aiBaseURL, model: aiModel, apiKey: apiKey)
    }

    func applyAIConfiguration(baseURL: String, model: String, key: String) throws {
        _ = try AISummaryRequest.endpointURL(baseURL)
        aiBaseURL = AISummaryRequest.normalizedBaseURL(baseURL)
        aiModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var languageTitle: String {
        RecognitionLanguage.title(for: languageCode)
    }
}
