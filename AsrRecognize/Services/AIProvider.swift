import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case mistral
    case appleOnDevice
    case deepSeek
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mistral:
            return "Mistral AI (EU)"
        case .appleOnDevice:
            return "Apple (auf dem Gerät)"
        case .deepSeek:
            return "DeepSeek"
        case .custom:
            return "Eigener Endpunkt"
        }
    }

    var shortTitle: String {
        switch self {
        case .mistral:
            return "Mistral EU"
        case .appleOnDevice:
            return "Apple lokal"
        case .deepSeek:
            return "DeepSeek"
        case .custom:
            return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .mistral:
            return "Inferenz in der EU über api.eu.mistral.ai. AVV/DPA des Anbieters prüfen."
        case .appleOnDevice:
            return "Läuft vollständig auf dem Gerät. Kein Transkript verlässt das iPhone oder iPad."
        case .deepSeek:
            return "OpenAI-kompatibel. Daten werden in China verarbeitet."
        case .custom:
            return "Beliebiger OpenAI-kompatibler Endpunkt. Datenschutz hängt vom Anbieter ab."
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .mistral:
            return "https://api.eu.mistral.ai/v1"
        case .appleOnDevice:
            return ""
        case .deepSeek:
            return "https://api.deepseek.com"
        case .custom:
            return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .mistral:
            return "mistral-large-latest"
        case .appleOnDevice:
            return "Apple Intelligence"
        case .deepSeek:
            return "deepseek-chat"
        case .custom:
            return "gpt-4o-mini"
        }
    }

    var requiresAPIKey: Bool {
        self != .appleOnDevice
    }

    var warning: String? {
        switch self {
        case .deepSeek:
            return "Für personenbezogene Daten in der EU nicht geeignet: Die Verarbeitung findet in China statt."
        default:
            return nil
        }
    }
}
