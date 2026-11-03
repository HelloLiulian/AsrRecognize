import Combine
import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let legacyAPIKey = "deepseek_api_key"
        static let language = "recognition_language"
        static let offline = "recognition_offline_only"
        static let autoSummary = "auto_summary"
        static let provider = "ai_provider"
        static let legacyBaseURL = "ai_base_url"
        static let legacyModel = "ai_model"
    }

    @Published var provider: AIProvider {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: Keys.provider)
            loadConfiguration(for: provider)
        }
    }

    @Published var aiBaseURL: String {
        didSet {
            guard !isLoadingConfiguration, provider.requiresAPIKey else { return }
            defaults.set(aiBaseURL, forKey: Self.baseURLKey(provider))
            apiKey = KeychainStore.read(Self.keychainAccount(for: aiBaseURL))
        }
    }

    @Published var aiModel: String {
        didSet {
            guard !isLoadingConfiguration, provider.requiresAPIKey else { return }
            defaults.set(aiModel, forKey: Self.modelKey(provider))
        }
    }

    @Published var apiKey: String {
        didSet {
            guard !isLoadingConfiguration, provider.requiresAPIKey else { return }
            KeychainStore.save(apiKey, for: Self.keychainAccount(for: aiBaseURL))
        }
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

    private let defaults = UserDefaults.standard
    private var isLoadingConfiguration = false

    init() {
        let savedLanguage = defaults.string(forKey: Keys.language)
        if let savedLanguage, savedLanguage != "zh-CN" {
            languageCode = savedLanguage
        } else {
            languageCode = "de-DE"
        }
        offlineOnly = defaults.bool(forKey: Keys.offline)
        autoSummarize = defaults.object(forKey: Keys.autoSummary) as? Bool ?? true

        let legacyBase = defaults.string(forKey: Keys.legacyBaseURL)
        let initialProvider: AIProvider
        if let raw = defaults.string(forKey: Keys.provider),
           let saved = AIProvider(rawValue: raw) {
            initialProvider = saved
        } else if let legacyBase, !legacyBase.isEmpty {
            initialProvider = legacyBase.localizedCaseInsensitiveContains("deepseek.com")
                ? .deepSeek
                : .custom
        } else {
            initialProvider = .mistral
        }
        provider = initialProvider

        switch initialProvider {
        case .appleOnDevice:
            aiBaseURL = ""
            aiModel = initialProvider.defaultModel
            apiKey = ""
        default:
            let storedBase = defaults.string(forKey: Self.baseURLKey(initialProvider))
            let migratedBase = legacyBase
                .flatMap { Self.inferredProvider(for: $0) == initialProvider ? $0 : nil }
            let base = storedBase ?? migratedBase ?? initialProvider.defaultBaseURL
            aiBaseURL = base

            let storedModel = defaults.string(forKey: Self.modelKey(initialProvider))
            let legacyModel = defaults.string(forKey: Keys.legacyModel)
            aiModel = storedModel ?? (initialProvider == .mistral ? nil : legacyModel) ?? initialProvider.defaultModel
            apiKey = KeychainStore.read(Self.keychainAccount(for: base))
        }

        defaults.set(initialProvider.rawValue, forKey: Keys.provider)

        let legacyKey = KeychainStore.read(Keys.legacyAPIKey)
        if !legacyKey.isEmpty {
            let targetBase = legacyBase ?? AIProvider.deepSeek.defaultBaseURL
            let account = Self.keychainAccount(for: targetBase)
            if KeychainStore.read(account).isEmpty {
                KeychainStore.save(legacyKey, for: account)
            }
            KeychainStore.delete(Keys.legacyAPIKey)
            if initialProvider != .appleOnDevice, account == Self.keychainAccount(for: aiBaseURL) {
                apiKey = KeychainStore.read(account)
            }
        }
    }

    static func keychainAccount(for baseURL: String) -> String {
        "ai-key:" + AISummaryRequest.normalizedBaseURL(baseURL)
    }

    private static func baseURLKey(_ provider: AIProvider) -> String {
        "ai_base_url.\(provider.rawValue)"
    }

    private static func modelKey(_ provider: AIProvider) -> String {
        "ai_model.\(provider.rawValue)"
    }

    private static func inferredProvider(for baseURL: String) -> AIProvider {
        baseURL.localizedCaseInsensitiveContains("deepseek.com") ? .deepSeek : .custom
    }

    private func loadConfiguration(for provider: AIProvider) {
        isLoadingConfiguration = true
        defer { isLoadingConfiguration = false }

        switch provider {
        case .appleOnDevice:
            aiBaseURL = ""
            aiModel = provider.defaultModel
            apiKey = ""
        default:
            let base = defaults.string(forKey: Self.baseURLKey(provider)) ?? provider.defaultBaseURL
            aiBaseURL = base
            aiModel = defaults.string(forKey: Self.modelKey(provider)) ?? provider.defaultModel
            apiKey = KeychainStore.read(Self.keychainAccount(for: base))
        }
    }

    var aiConfiguration: AIConfiguration {
        AIConfiguration(baseURL: aiBaseURL, model: aiModel, apiKey: apiKey)
    }

    func applyAIConfiguration(baseURL: String, model: String, key: String) throws {
        guard provider.requiresAPIKey else { return }

        let normalized = AISummaryRequest.normalizedBaseURL(baseURL)
        _ = try AISummaryRequest.endpointURL(normalized)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoadingConfiguration = true
        aiBaseURL = normalized
        aiModel = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
        apiKey = trimmedKey
        isLoadingConfiguration = false

        defaults.set(aiBaseURL, forKey: Self.baseURLKey(provider))
        defaults.set(aiModel, forKey: Self.modelKey(provider))
        KeychainStore.save(trimmedKey, for: Self.keychainAccount(for: normalized))
    }

    var hasAPIKey: Bool {
        provider.requiresAPIKey
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSummarize: Bool {
        switch provider {
        case .appleOnDevice:
            return AISummaryService.isOnDeviceAvailable
        default:
            return hasAPIKey
        }
    }

    var summarySetupMessage: String {
        switch provider {
        case .appleOnDevice:
            return AISummaryService.onDeviceAvailabilityMessage
        case .deepSeek:
            return "Bitte hinterlegen Sie einen DeepSeek-API-Schlüssel. Hinweis: Die Verarbeitung findet in China statt."
        default:
            return "Bitte hinterlegen Sie zuerst einen API-Schlüssel in den Einstellungen."
        }
    }

    var activeModelTitle: String {
        provider == .appleOnDevice ? "Apple Intelligence" : aiModel
    }

    var languageTitle: String {
        RecognitionLanguage.title(for: languageCode)
    }
}
