# Protokolle

Eine minimalistische iOS-App für Besprechungsprotokolle im technischen Dark-Design: Live-Transkription oder Import von Audiodateien, lokale Speicherung und optionale KI-Zusammenfassung.

- Durchgehend deutsche Oberfläche inklusive Datums- und Dauerformaten
- iPhone und iPad (iPad im Hoch- und Querformat, adaptive Inhaltsbreite)
- SwiftUI + SwiftData + Apple Speech
- KI-Zusammenfassung mit Anbieter-Auswahl: **Mistral AI (EU, Standard)**, **Apple Intelligence auf dem Gerät** oder optional **DeepSeek** für Nicht-EU-Märkte
- Import von Audiodateien mit Wiederaufnahme nach Unterbrechung
- iOS 18+ (Apple Intelligence erfordert iOS 26 und ein unterstütztes Gerät)
- Dunkle Oberfläche, Live-Wellenform, Glaskarten, haptisches Feedback

> ⚠️ Dieses Projekt wurde unter Windows erzeugt. Die iOS-App muss auf macOS mit Xcode gebaut werden; unter Windows läuft sie nicht.

---

## Projekt starten (ca. 1 Minute)

1. Den Ordner `AsrRecognize` auf einen Mac kopieren.
2. `AsrRecognize.xcodeproj` per Doppelklick oder mit Xcode öffnen.
3. Oben als Scheme **AsrRecognize** und als Ziel einen **iPhone- oder iPad-Simulator** (z. B. iPhone 16) oder ein angeschlossenes Gerät wählen.
4. Mit **⌘R** starten.

**Simulator**: keine Signatur nötig, sofort lauffähig.
**Gerät**: Target auswählen → `Signing & Capabilities` → `Automatically manage signing` aktivieren → Apple-ID-Team wählen. Falls die Bundle-ID belegt ist, `com.liulian.Protokolle` in `com.deinName.Protokolle` ändern.

### Voraussetzungen

| Komponente | Anforderung |
| --- | --- |
| macOS | 14.5 oder neuer (Voraussetzung für Xcode 16) |
| Xcode | 16 oder neuer (für Apple Intelligence: Xcode 26) |
| Laufzeitsystem | iOS 18.0+ (Apple Intelligence auf dem Gerät: iOS 26 + unterstütztes Gerät) |
| Netzwerk | System-Spracherkennung und Cloud-KI benötigen Netzwerk (geräteinterne Erkennung ist umschaltbar; Apple Intelligence läuft offline) |

> Die Spracherkennung kann im Simulator instabil sein oder fehlen. Für den vollen Funktionsumfang ein echtes Gerät verwenden.

---

## Erste Schritte

1. App öffnen und unten auf **Aufnahme starten** tippen.
2. Zugriff auf **Mikrofon** und **Spracherkennung** erlauben.
3. Beim Sprechen erscheint der Text live; **Fertig** speichert das Protokoll.
4. In der Detailansicht stehen zur Verfügung:
   - Wiedergabe der Originalaufnahme
   - Titel bearbeiten
   - Transkript ansehen / KI-Zusammenfassung erzeugen
   - Protokoll exportieren oder teilen

### KI-Anbieter konfigurieren (optional)

1. Oben rechts auf der Startseite **Einstellungen** öffnen.
2. Unter **KI-ANBIETER** einen Anbieter wählen:
   - **Mistral AI (EU)** – Standard, `https://api.eu.mistral.ai/v1` mit `mistral-large-latest`. Inferenz in der EU; AVV/DPA mit Mistral abschließen.
   - **Apple (auf dem Gerät)** – Apple Intelligence, ohne API-Schlüssel. Das Transkript verlässt das Gerät nicht. Erfordert iOS 26, ein unterstütztes Gerät und aktivierte Apple Intelligence.
   - **DeepSeek** – optional für Nicht-EU-Märkte, `https://api.deepseek.com` mit `deepseek-chat`. **Nicht für personenbezogene Daten in der EU geeignet**, da die Verarbeitung in China stattfindet.
   - **Eigener Endpunkt** – jeder OpenAI-kompatible Endpunkt.
3. Bei Cloud-Anbietern **Basis-URL**, **Modell** und **API-Schlüssel** prüfen und **Speichern** tippen. Die Konfiguration und der Schlüssel werden pro Anbieter getrennt gespeichert.
4. In einer Protokoll-Detailansicht **Zusammenfassung** wählen oder in den Einstellungen **Automatisch zusammenfassen** aktiviert lassen.

> Bei Cloud-Anbietern wird ausschließlich das Transkript gesendet. Audio verlässt das Gerät nicht. Bei Apple Intelligence bleiben Transkript und Protokoll vollständig lokal; lange Besprechungen werden in Abschnitte aufgeteilt und zweistufig zusammengefasst.

---

## Funktionen

- **Live-Transkription**: System-Spracherkennung (Deutsch/Englisch), alle 50 Sekunden wird die Erkennung nahtlos fortgesetzt – auch lange Besprechungen brechen nicht ab.
- **Aufnahme**: im App-Sandbox-Ordner `Documents/Recordings` (CAF), Wiedergabe in der Detailansicht.
- **Lokale Speicherung**: Protokolle, Transkripte und Zusammenfassungen liegen in SwiftData; das Löschen eines Protokolls entfernt auch die Aufnahme.
- **KI-Zusammenfassung**: strukturiertes JSON mit Zusammenfassung, Kernpunkten, Aufgaben (Verantwortlich/Frist) und Beschlüssen.
- **Suche**: auf der Startseite nach Titel oder Transkripttext.
- **Audiodateien importieren**: m4a, mp3, wav, caf, aac, aiff, flac – bis 2 Stunden bzw. 1,5 GB, mit Fortschritt, Pause und Wiederaufnahme.
- **Export**: Protokoll als Textdatei (`.txt`) oder Originalaudio.
- **Datenschutz**: API-Schlüssel im Schlüsselbund; kein Konto, keine Cloud-Synchronisierung, kein Tracking-SDK.

### Spracherkennung / Sprache

Die App verwendet ausschließlich die **System-Spracherkennung** von Apple Speech – live und beim Import. Die Option **Nur auf dem Gerät** ist standardmäßig aktiv und hält die Erkennung offline; ohne diese Option kann Apple die Erkennung auf seinen Servern durchführen. Die App bündelt kein lokales ASR-Modell mehr.

Die Erkennungssprache lässt sich zwischen **Deutsch** und **English** umschalten; die Änderung gilt für die nächste Aufnahme bzw. den nächsten Import.

---

## Audiodateien importieren

1. Auf „Audiodatei importieren“ tippen und eine Datei aus „Dateien“ wählen (m4a, mp3, wav, caf, aac, aiff, flac; maximal 2 Stunden / 1,5 GB).
2. Titel und Sprache prüfen und die Transkription starten.
3. Die App bleibt geöffnet; bei Unterbrechung kann die Transkription fortgesetzt werden.

## Export

Im Protokoll-Menü „Exportieren“ → „Als Text (.txt)“ oder „Audio exportieren“ (Originalformat).

## Tests

CI führt reine Logiktests aus:

```bash
bash tools/run-logic-tests.sh
```

Die Logiktests laufen als temporäres SwiftPM-Paket (`ProtokollLogic`) und benötigen kein iOS-Simulator-Gerät. Der vollständige App-Build wird in GitHub Actions auf `main`, bei manuellem Start oder bei Commits mit `[full-ci]` ausgeführt.

---

## Projektstruktur

```
AsrRecognize/
├── AsrRecognize.xcodeproj        # Projektdatei (inkl. geteiltem Scheme)
├── AsrRecognize/
│   ├── App/                      # App-Einstieg, SwiftData-Container
│   ├── Views/
│   │   ├── HomeView.swift        # Protokollliste, Suche, Statistik, Import
│   │   ├── RecordingView.swift   # Aufnahme und Live-Transkript
│   │   ├── ImportSetupView.swift # Titel und Sprache für den Import
│   │   ├── ImportProgressView.swift # Fortschritt, Pause, Wiederaufnahme
│   │   ├── MeetingDetailView.swift
│   │   ├── SummaryContentView.swift
│   │   └── SettingsView.swift
│   ├── Services/
│   │   ├── LiveTranscriber.swift # AVAudioEngine + Speech, Live-Transkript
│   │   ├── AppleChunkEngine.swift # Apple Speech für Dateiabschnitte
│   │   ├── AudioFileTranscriber.swift # Import-Pipeline mit Checkpoints
│   │   ├── ImportJobStore.swift  # Auftrags- und Segment-Checkpoints
│   │   ├── ImportValidation.swift
│   │   ├── ExportService.swift
│   │   ├── AIProvider.swift      # Anbieter-Presets (Mistral EU, Apple lokal, DeepSeek, Custom)
│   │   ├── AISummaryService.swift / AISummaryRequest.swift
│   │   ├── AppleFoundationSummarizer.swift # Apple Intelligence, zweistufige Zusammenfassung
│   │   ├── AudioProcessing/      # Chunk-Engine-Protokoll, 16-kHz-Resampling, VAD
│   │   ├── AudioPlayer.swift
│   │   ├── AudioStorage.swift
│   │   ├── KeychainStore.swift
│   │   └── AppSettings.swift
│   ├── Models/                   # Meeting / MeetingSummary / TranscriptSegment
│   ├── Design/                   # Theme, Komponenten, Wellenform
│   ├── Utilities/                # Formatierung, Haptik
│   ├── Assets.xcassets           # AppIcon / AccentColor
│   └── Info.plist                # Berechtigungen, Hintergrund-Audio, Startbildschirm
├── ProtokollTests/               # Reine Logiktests (ohne UI)
├── tools/
│   ├── generate_xcodeproj.py     # Erzeugt .xcodeproj neu
│   ├── run-logic-tests.sh        # Logiktests über SwiftPM
│   └── make_icon.py              # Erzeugt das 1024er-AppIcon
├── docs/                         # Entwurf, Plan und Spezifikation
└── README.md
```

Die Projektdatei wird per Skript erzeugt; Quelldateien werden nach Verzeichnis kompiliert. Für die normale Nutzung ist kein Skriptlauf nötig.

---

## Häufige Fragen

**Q: Beim Bauen erscheint ein Signing-Fehler?**
Für ein echtes Gerät in `Signing & Capabilities` ein Team auswählen; der Simulator benötigt keine Signatur.

**Q: Die App hängt bei „Mikrofon wird vorbereitet“?**
Prüfen, ob Mikrofon- und Spracherkennungszugriff in den Systemeinstellungen erlaubt sind; im Simulator sicherstellen, dass das Mac-Mikrofon verfügbar ist.

**Q: Es wird kein Text erkannt / die Erkennung bricht ab?**
Apple Speech hängt von Netzwerk und Systemdiensten ab. Netzwerk prüfen, ein echtes Gerät verwenden oder **Nur auf dem Gerät** deaktivieren und erneut versuchen.

**Q: Die KI-Zusammenfassung meldet einen Fehler?**
Bei Cloud-Anbietern: falscher Schlüssel (401), unzureichendes Guthaben (402), zu viele Anfragen (429), Zeitüberschreitung. Einstellungen prüfen und erneut versuchen. Pro Anfrage werden bis zu 120.000 Zeichen analysiert; darüber hinausgehender Text wird gekürzt und die Oberfläche weist darauf hin.

**Q: Apple Intelligence wird als nicht verfügbar angezeigt?**
Die lokale KI benötigt iOS 26, ein unterstütztes Gerät (iPhone 15 Pro oder neuer, iPad mit M-Chip) und aktivierte Apple Intelligence in den iOS-Einstellungen. Alternativ einen Cloud-Anbieter wie Mistral AI (EU) wählen.

**Q: Warum ist DeepSeek nicht vorausgewählt?**
DeepSeek verarbeitet Daten in China. Für personenbezogene Daten in der EU ist der Anbieter daher nicht geeignet. Standard ist Mistral AI mit EU-Inferenz; DeepSeek bleibt für Nicht-EU-Märkte als Option erhalten.

**Q: Wo liegen die Daten?**
Aufnahmen im App-Sandbox-Ordner `Documents/Recordings`, Protokolle in der SwiftData-Datenbank, API-Schlüssel im Schlüsselbund. Beim Deinstallieren der App werden alle Daten gelöscht.

**Q: „Unvollständige Transkription“ auf der Startseite?**
Ein Import wurde unterbrochen (z. B. App beendet). Der Auftrag erscheint als Banner und kann fortgesetzt werden; bereits gespeicherte Abschnitte werden nicht erneut verarbeitet. Über **Verwerfen** lassen sich Auftrag und kopierte Audiodatei entfernen.

**Q: Der Import dauert länger als die Aufnahme?**
Das ist erwartbar. Die Erkennung arbeitet abschnittsweise; der Fortschritt und eine Restzeit-Schätzung werden angezeigt. Die App muss während des Imports geöffnet bleiben; ein Wechsel in den Hintergrund pausiert den Auftrag und er kann danach fortgesetzt werden.

**Q: Unterstützt die App iPad / Querformat?**
Die App läuft auf iPhone und iPad. Das iPhone bleibt im Hochformat; auf dem iPad sind Hoch- und Querformat sowie Multitasking möglich. Auf großen Bildschirmen wird der Inhalt auf eine lesbare Breite begrenzt und zentriert. Deployment-Target iOS 18.

---

## Xcode-Projekt neu generieren (optional)

```bash
cd AsrRecognize
python3 tools/generate_xcodeproj.py   # schreibt project.pbxproj und das geteilte Scheme neu
python3 tools/make_icon.py            # erzeugt das AppIcon neu (benötigt Pillow, numpy)
```

Wenn Xcode das Projekt fehlerhaft öffnet, zuerst das Skript ausführen und das Projekt erneut öffnen.

---

## Ohne Mac: Cloud-Build über GitHub Actions

Das Repository enthält `.github/workflows/ios-build.yml`; weder Mac noch Signaturzertifikat sind nötig. Die Logiktests laufen bei jedem Push auf `main` oder einen `feature/**`-Branch. Der App-Build für den Simulator läuft auf `main`, bei manuellem Start oder bei Commits mit `[full-ci]`; die unsignierte Geräte-IPA läuft auf `main` oder bei manuellem Start.

| Job / Artifact | Inhalt | Zweck |
| --- | --- | --- |
| `logic-tests` | SwiftPM-Logiktests ohne UI | Schnelle Regressionprüfung bei jedem Push |
| `simulator-app` → `AsrRecognize-simulator-appetize` | Debug-Build, einige zehn MB | Hochladen auf Appetize.io, Oberfläche im Browser bedienen |
| `unsigned-ipa` → `AsrRecognize-unsigned-ipa` | Release-Gerätebuild ohne Signatur | Mit Sideloadly signieren und auf dem iPhone installieren |

- Die App bündelt kein Modell mehr; alle Builds sind klein und laufen in wenigen Minuten durch.
- Apple Intelligence ist im Simulator nicht verfügbar. Für die lokale Zusammenfassung ein unterstütztes Gerät mit iOS 26 verwenden; im Simulator einen Cloud-Anbieter konfigurieren.

### 1. Projekt zu GitHub pushen

Zuerst ein leeres Repository auf GitHub anlegen (öffentlich oder privat), dann im Projektordner:

```bash
git init
git add .
git commit -m "Protokoll iOS app"
git branch -M main
git remote add origin https://github.com/<benutzername>/<repository>.git
git push -u origin main
```

### 2. Cloud-Build starten

Repository-Seite öffnen → **Actions** → links **Build AsrRecognize** → **Run workflow** → `main` wählen und starten. Beide Build-Jobs dauern in der Regel 3–6 Minuten. Danach unter **Artifacts** der Ausführung herunterladen:

- `AsrRecognize-simulator-appetize.zip`: einmal entpacken, darin liegt `AsrRecognize-simulator.zip` (mit der `.app`)
- `AsrRecognize-unsigned-ipa.zip`: einmal entpacken, darin liegt `AsrRecognize-unsigned.ipa`

> Das von GitHub heruntergeladene Artifact ist selbst eine ZIP-Datei; nicht direkt bei Appetize hochladen.

> Actions sind für öffentliche Repositories in der Regel kostenlos; private Repositories verbrauchen macOS-Build-Minuten, die zehnfach abgerechnet werden.

### 3. Im Browser öffnen (Appetize.io, ohne lokale Installation)

1. Bei [Appetize.io](https://appetize.io) registrieren und anmelden.
2. **New App** → Plattform **iOS** → die entpackte `AsrRecognize-simulator.zip` hochladen.
3. Nach dem Upload den Link der Detailseite öffnen und die App im Browser bedienen.

Hinweis: Das kostenlose Kontingent umfasst etwa 30 Minuten pro Monat und 3 Minuten pro Sitzung. Appetize dient vor allem der Vorschau von Oberfläche und Interaktion; **Mikrofon, Apple Speech und Apple Intelligence stehen nicht zur Verfügung**. Für echte Transkription ein Gerät verwenden.

### 4. Auf dem iPhone oder iPad installieren (Windows + Sideloadly)

1. [Sideloadly](https://sideloadly.io) unter Windows installieren.
2. Das iPhone oder iPad per USB verbinden und `AsrRecognize-unsigned.ipa` in Sideloadly ziehen.
3. Apple-ID eingeben (kostenloses Konto genügt) und **Start** antippen, um zu signieren und zu installieren.
4. Nach der ersten Installation den Entwicklermodus aktivieren: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten und neu starten.
5. Bei „Nicht vertrauenswürdiger Entwickler“: **Einstellungen → Allgemein → VPN & Geräteverwaltung** → der Apple-ID vertrauen.

Mit einer kostenlosen Apple-ID signierte Apps **laufen nach 7 Tagen ab**; danach mit denselben Schritten erneut signieren. Nach der Installation in den Einstellungen die Transkription auf **Nur auf dem Gerät** stellen, um ohne Netzwerk zu erkennen.

---

## Veröffentlichung (App Store)

### 1. Datenschutz- und Support-Seite

`site/` enthält die deutsche und englische Datenschutzerklärung, die Support-Seite und ein Impressum. Der Workflow **Pages** veröffentlicht den Ordner nach jedem Push auf `main`.

1. GitHub → **Settings → Pages → Source: GitHub Actions**.
2. Nach dem ersten Lauf: `https://helloliulian.github.io/AsrRecognize/`.
3. **Vorher alle Platzhalter in eckigen Klammern** in `site/privacy/de.html`, `site/privacy/en.html`, `site/support.html` und `fastlane/metadata/copyright.txt` durch echte Angaben ersetzen.

### 2. TestFlight-Upload über GitHub Actions

Workflow **Build AsrRecognize** manuell starten und **upload_to_testflight** aktivieren. Der Job archiviert, signiert mit automatischer Bereitstellung und lädt direkt zu TestFlight hoch. Die Build-Nummer kommt aus `GITHUB_RUN_NUMBER`.

Benötigte Repository-Secrets:

| Secret | Inhalt |
| --- | --- |
| `APPLE_TEAM_ID` | Team-ID aus dem Developer Portal |
| `APP_STORE_CONNECT_KEY_ID` | Key-ID des App Store Connect API Key |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer-ID des API Key |
| `APP_STORE_CONNECT_API_KEY` | Base64 des `.p8`-Schlüssels |
| `BUILD_CERTIFICATE_BASE64` | Base64 des Distribution-Zertifikats (`.p12`) |
| `P12_PASSWORD` | Passwort des `.p12` |
| `KEYCHAIN_PASSWORD` | optional, temporäres Keychain-Passwort |

Fehlt eines der Pflicht-Secrets, wird der Upload-Job mit einer Warnung übersprungen. Alternativ kann **Xcode Cloud** in App Store Connect den Build und Upload ohne lokalen Mac übernehmen.

### 3. Store-Metadaten

`fastlane/metadata/de-DE/` enthält Name, Untertitel, Keywords, Beschreibung, Promo-Text, URLs und Versionshinweise; `fastlane/metadata/review_information/notes.txt` die Notizen für die Prüfung. Die Werte können manuell in App Store Connect übernommen oder auf einem Mac mit `fastlane deliver --skip_binary_upload` hochgeladen werden.

### 4. Noch manuell zu erledigen

- Apple Developer Program abschließen und die Bundle-ID `com.liulian.Protokolle` registrieren.
- In der EU zusätzlich die **Trader-Erklärung** (DSA) in App Store Connect ausfüllen.
- App-Privacy-Fragebogen: Audio (Spracherkennung, ggf. über Apple), Nutzerinhalte (Transkript bei Cloud-KI), keine Verknüpfung mit Identität, kein Tracking.
- Altersfreigabe, Kategorie (Productivity), Copyright und Support-URL eintragen.
- iPhone-Screenshots in 6,9″ (1320 × 2868) ergänzen; die vorhandenen Bilder sind nur iPad (2064 × 2752).
- Screenshots mit einer echten Aufnahme statt Mock-Text neu erstellen.
- TestFlight-Internaltest auf einem echten Gerät durchführen.
