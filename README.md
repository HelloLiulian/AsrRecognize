# Protokoll

Eine minimalistische iOS-App für Besprechungsprotokolle im technischen Dark-Design: Live-Transkription oder Import von Audiodateien, lokale Speicherung und optionale KI-Zusammenfassung.

- Durchgehend deutsche Oberfläche inklusive Datums- und Dauerformaten
- SwiftUI + SwiftData + Apple Speech + OpenAI-kompatible KI (Standard: DeepSeek)
- Optionales lokales Qwen3-ASR (vollständig Core ML, offline), basiert auf speech-swift
- Import von Audiodateien mit Wiederaufnahme nach Unterbrechung
- iOS 18+
- Dunkle Oberfläche, Live-Wellenform, Glaskarten, haptisches Feedback

> ⚠️ Dieses Projekt wurde unter Windows erzeugt. Die iOS-App muss auf macOS mit Xcode gebaut werden; unter Windows läuft sie nicht.

---

## Projekt starten (ca. 1 Minute)

1. Den Ordner `AsrRecognize` auf einen Mac kopieren.
2. `AsrRecognize.xcodeproj` per Doppelklick oder mit Xcode öffnen.
3. Oben als Scheme **AsrRecognize** und als Ziel einen **iPhone-Simulator** (z. B. iPhone 16) oder ein angeschlossenes Gerät wählen.
4. Mit **⌘R** starten.

**Simulator**: keine Signatur nötig, sofort lauffähig.
**Gerät**: Target auswählen → `Signing & Capabilities` → `Automatically manage signing` aktivieren → Apple-ID-Team wählen. Falls die Bundle-ID belegt ist, `com.liulian.AsrRecognize` in `com.deinName.AsrRecognize` ändern.

### Voraussetzungen

| Komponente | Anforderung |
| --- | --- |
| macOS | 14.5 oder neuer (Voraussetzung für Xcode 16) |
| Xcode | 15 oder neuer (empfohlen: 16) |
| Laufzeitsystem | iOS 18.0+ (Simulator oder Gerät; das lokale Qwen3-Modell benötigt ein echtes Gerät) |
| Netzwerk | System-Spracherkennung und KI-Zusammenfassung benötigen Netzwerk (geräteinterne Erkennung ist umschaltbar) |

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
2. **Basis-URL**, **Modell** und **API-Schlüssel** eintragen. Voreinstellung: `https://api.deepseek.com` und `deepseek-flash`; jeder OpenAI-kompatible Endpunkt funktioniert.
3. Auf **Speichern** tippen. Der Schlüssel wird im Systemschlüsselbund abgelegt.
4. In einer Protokoll-Detailansicht **Zusammenfassung** wählen oder in den Einstellungen **Automatisch zusammenfassen** aktiviert lassen.

> Es wird ausschließlich das Transkript an den konfigurierten Anbieter gesendet. Audio verlässt das Gerät nicht.

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

### Spracherkennungs-Engines / Sprache

In den Einstellungen stehen zwei Engines zur Wahl:

- **System-Spracherkennung**: Apple Speech, Text in Echtzeit, **Nur auf dem Gerät** reduziert die Netzwerknutzung.
- **Lokales Qwen3**: Qwen3-ASR 0.6B, vollständige Core-ML-Inferenz, komplett offline. Die Ausgabe erfolgt abschnittsweise (nicht wortweise). Das Modell ist ca. 0,9 GB groß und wird mit der App ausgeliefert; der erste Ladevorgang dauert etwa 1 Minute. Erfordert iOS 18 und ein echtes Gerät (im Simulator fehlt die ANE). Fehlt das Modell, weist die App darauf hin und bietet den Wechsel zur System-Spracherkennung an.

Die Erkennungssprache lässt sich zwischen **Deutsch** und **English** umschalten; die Änderung gilt für die nächste Aufnahme bzw. den nächsten Import.

---

## Audiodateien importieren

1. Auf „Audiodatei importieren“ tippen und eine Datei aus „Dateien“ wählen (m4a, mp3, wav, caf, aac, aiff, flac; maximal 2 Stunden / 1,5 GB).
2. Engine (Lokales Qwen3 oder System-Spracherkennung) und Sprache wählen.
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
│   │   ├── ImportSetupView.swift # Titel, Engine und Sprache für den Import
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
│   │   ├── AISummaryService.swift / AISummaryRequest.swift
│   │   ├── Qwen3/                # Lokales Qwen3-ASR: Engine, VAD, Resampling, Session
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
│   ├── prepare-model.sh          # Lädt und kompiliert das Qwen3-CoreML-Modell
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
Typische Ursachen: falscher Schlüssel (401), unzureichendes Guthaben (402), zu viele Anfragen (429), Zeitüberschreitung. Einstellungen prüfen und erneut versuchen. Pro Anfrage werden bis zu 120.000 Zeichen analysiert; darüber hinausgehender Text wird gekürzt und die Oberfläche weist darauf hin.

**Q: Wo liegen die Daten?**
Aufnahmen im App-Sandbox-Ordner `Documents/Recordings`, Protokolle in der SwiftData-Datenbank, API-Schlüssel im Schlüsselbund. Beim Deinstallieren der App werden alle Daten gelöscht.

**Q: „Unvollständige Transkription“ auf der Startseite?**
Ein Import wurde unterbrochen (z. B. App beendet). Der Auftrag erscheint als Banner und kann fortgesetzt werden; bereits gespeicherte Abschnitte werden nicht erneut verarbeitet. Über **Verwerfen** lassen sich Auftrag und kopierte Audiodatei entfernen.

**Q: Der Import dauert länger als die Aufnahme?**
Das ist erwartbar. Die lokale Erkennung arbeitet abschnittsweise; der Fortschritt und eine Restzeit-Schätzung werden angezeigt. Die App muss während des Imports geöffnet bleiben; ein Wechsel in den Hintergrund pausiert den Auftrag und er kann danach fortgesetzt werden.

**Q: „Modell nicht enthalten“ beim lokalen Qwen3?**
Das Repository enthält nicht das 0,9-GB-Modell. Auf einem Mac `bash tools/prepare-model.sh` ausführen und neu bauen oder den Build mit Modell über GitHub Actions nutzen (siehe unten).

**Q: Unterstützt die App iPad / Querformat?**
Derzeit nur iPhone im Hochformat, Deployment-Target iOS 18.

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

Das Repository enthält `.github/workflows/ios-build.yml`; weder Mac noch Signaturzertifikat sind nötig. Die Logiktests laufen bei jedem Push auf `main` oder einen `feature/**`-Branch. Der App-Build für den Simulator läuft auf `main`, bei manuellem Start oder bei Commits mit `[full-ci]`; der Geräte-Build mit Modell läuft nur auf `main` oder bei manuellem Start.

| Job / Artifact | Inhalt | Zweck |
| --- | --- | --- |
| `logic-tests` | SwiftPM-Logiktests ohne UI | Schnelle Regressionprüfung bei jedem Push |
| `simulator-app` → `AsrRecognize-simulator-appetize` | Debug-Build ohne Modell, einige zehn MB | Hochladen auf Appetize.io, Oberfläche im Browser bedienen |
| `offline-ipa` → `AsrRecognize-unsigned-ipa` | Lädt und kompiliert das Qwen3-Modell (ca. 0,9 GB), Release-Gerätebuild | Mit Sideloadly signieren und auf dem iPhone installieren, Offline-Transkription |

- Der Simulator besitzt keine ANE; das lokale Qwen3-Modell läuft dort nicht. Deshalb enthält das Simulator-Paket **kein Modell** und nutzt die System-Spracherkennung.
- Der Job mit Modell dauert länger: Download und `coremlcompiler` benötigen etwa 20–40 Minuten, das Artefakt ist ca. 0,9 GB groß.
- Wenn nur die Kompilierung geprüft werden soll, beim manuellen Start `include_model` deaktivieren.

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

Repository-Seite öffnen → **Actions** → links **Build AsrRecognize** → **Run workflow** → `main` wählen und starten. Der Simulator-Job dauert etwa 3–6 Minuten; der Job mit Modell meist 20–40 Minuten (abhängig von der Download-Geschwindigkeit bei Hugging Face). Danach unter **Artifacts** der Ausführung herunterladen:

- `AsrRecognize-simulator-appetize.zip`: einmal entpacken, darin liegt `AsrRecognize-simulator.zip` (mit der `.app`)
- `AsrRecognize-unsigned-ipa.zip`: einmal entpacken, darin liegt `AsrRecognize-unsigned.ipa`

> Das von GitHub heruntergeladene Artifact ist selbst eine ZIP-Datei; nicht direkt bei Appetize hochladen.

> Actions sind für öffentliche Repositories in der Regel kostenlos; private Repositories verbrauchen macOS-Build-Minuten, die zehnfach abgerechnet werden.

### 3. Im Browser öffnen (Appetize.io, ohne lokale Installation)

1. Bei [Appetize.io](https://appetize.io) registrieren und anmelden.
2. **New App** → Plattform **iOS** → die entpackte `AsrRecognize-simulator.zip` hochladen.
3. Nach dem Upload den Link der Detailseite öffnen und die App im Browser bedienen.

Hinweis: Das kostenlose Kontingent umfasst etwa 30 Minuten pro Monat und 3 Minuten pro Sitzung. Appetize dient vor allem der Vorschau von Oberfläche und Interaktion; **Mikrofon, Apple Speech und lokale Modellinferenz stehen nicht zur Verfügung**. Für echte Transkription ein Gerät verwenden.

### 4. Auf dem iPhone installieren (Windows + Sideloadly)

1. [Sideloadly](https://sideloadly.io) unter Windows installieren.
2. Das iPhone per USB verbinden und `AsrRecognize-unsigned.ipa` in Sideloadly ziehen.
3. Apple-ID eingeben (kostenloses Konto genügt) und **Start** antippen, um zu signieren und zu installieren.
4. Nach der ersten Installation am iPhone den Entwicklermodus aktivieren: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten und neu starten.
5. Bei „Nicht vertrauenswürdiger Entwickler“: **Einstellungen → Allgemein → VPN & Geräteverwaltung** → der Apple-ID vertrauen.

Mit einer kostenlosen Apple-ID signierte Apps **laufen nach 7 Tagen ab**; danach mit denselben Schritten erneut signieren. Nach der Installation in den Einstellungen die Engine auf **Lokales Qwen3** stellen, um offline zu transkribieren (erster Ladevorgang ca. 1 Minute).
