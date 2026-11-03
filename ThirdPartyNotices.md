# Third-Party Notices

Die App bündelt keine Modelle oder Bibliotheken von Drittanbietern mehr. Die frühere lokale Qwen3-ASR-Integration (Core ML, speech-swift, mlx-swift, swift-transformers) wurde vollständig entfernt.

## Apple-Systemframeworks

- Verwendet werden von iOS bereitgestellte Frameworks: SwiftUI, SwiftData, AVFoundation, Speech und – sofern verfügbar – FoundationModels (Apple Intelligence).
- Es gelten die Lizenzbedingungen des Apple-SDK bzw. von iOS.
- Apple Intelligence ist nur auf unterstützten Geräten mit iOS 26 und aktivierter Apple Intelligence verfügbar.

## Externe KI-Anbieter (optional)

Die KI-Zusammenfassung kann optional einen vom Benutzer konfigurierten Cloud-Anbieter aufrufen. Es wird ausschließlich das Transkript übertragen. Für die Nutzung gelten die jeweiligen Bedingungen und Datenschutzvereinbarungen des Anbieters:

- Mistral AI (EU): https://mistral.ai/terms
- DeepSeek: https://www.deepseek.com (Verarbeitung in China; für personenbezogene Daten in der EU nicht geeignet)
- Eigene OpenAI-kompatible Endpunkte: Bedingungen des jeweiligen Betreibers

Die App enthält keinerlei API-Schlüssel oder Zugangsdaten von Drittanbietern. Schlüssel werden ausschließlich lokal im iOS-Schlüsselbund gespeichert.
