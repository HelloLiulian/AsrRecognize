# Protokoll（德语会议纪要 App）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有中文会议 App 改造成全德语、面向德国用户的 Protokoll，支持 ≤2 小时音频导入、本地/系统双引擎转写、断点续转、自定义 OpenAI 兼容 AI 纪要与 TXT/音频导出。

**Architecture:** 复用现有 SwiftUI + SwiftData 架构。新增统一分块流水线 `AudioFileTranscriber`（AVAudioFile 流式读取 → Audio16kConverter → VoiceActivityDetector → `ChunkTranscriptionEngine`），用 `ImportJobStore` 持久化检查点；Apple Speech 新增 `AppleChunkEngine` 适配器。纯逻辑（格式化、导出、检查点、校验、AI 请求）保持 Foundation-only，由 CI 脚本组装成临时 Swift Package 跑 `swift test`。

**Tech Stack:** Swift 5 / iOS 18 / SwiftUI / SwiftData / AVFoundation / Speech / CoreML（Qwen3-ASR via speech-swift）/ XCTest（SwiftPM 临时包）/ GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-10-31-german-protokoll-app-design.md`

---

## 0. 工作方式与前置

- 本机是 Windows，**没有 Swift/Xcode**。不要尝试本地 `xcodebuild` 或 `swift test`；所有编译与测试验证都通过 GitHub Actions。
- 每个任务结束都提交；每个任务中的“验证”步骤默认是：`python tools/generate_xcodeproj.py`（新增/删除 Swift 文件后必须执行）→ `git push` → 等待 CI 结果。
- CI 推送命令（在 repo 根目录）：

```bash
git push -u origin feature/german-protokoll
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

- CI 首次运行前先完成 Task 1 的分支与工作流改造。Task 1 之后，feature 分支只跑「逻辑测试 + 模拟器构建」，真机 IPA 只在 main 或手动触发时构建，以免每次都下载 0.9GB 模型。
- 生成工程脚本会枚举 `AsrRecognize/**/*.swift`；**新增或删除 .swift 文件后必须运行** `python tools/generate_xcodeproj.py` 并提交 `AsrRecognize.xcodeproj/project.pbxproj`。

---

### Task 1: 建立 CI 快速反馈环（分支 + 逻辑测试脚本）

**Files:**
- Create: `tools/run-logic-tests.sh`
- Create: `ProtokollTests/SmokeTests.swift`
- Modify: `.github/workflows/ios-build.yml`

- [ ] **Step 1: 创建功能分支**

```bash
cd /c/Users/liulian/gh-work/AsrRecognize
git checkout -b feature/german-protokoll
```

- [ ] **Step 2: 写逻辑测试运行脚本**

创建 `tools/run-logic-tests.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${RUNNER_TEMP:-/tmp}/ProtokollLogicTests"
rm -rf "$TMP"
mkdir -p "$TMP/Sources/ProtokollLogic" "$TMP/Tests/ProtokollLogicTests"

FILES=(
  "AsrRecognize/Utilities/Formatters.swift"
  "AsrRecognize/Models/TranscriptSegment.swift"
  "AsrRecognize/Models/MeetingSummary.swift"
  "AsrRecognize/Services/RecognitionLanguage.swift"
  "AsrRecognize/Services/ExportService.swift"
  "AsrRecognize/Services/ImportJobStore.swift"
  "AsrRecognize/Services/ImportValidation.swift"
  "AsrRecognize/Services/AISummaryRequest.swift"
)

for f in "${FILES[@]}"; do
  if [ -f "$ROOT/$f" ]; then cp "$ROOT/$f" "$TMP/Sources/ProtokollLogic/"; fi
done

if [ -d "$ROOT/ProtokollTests" ]; then
  cp "$ROOT"/ProtokollTests/*.swift "$TMP/Tests/ProtokollLogicTests/"
fi

cat > "$TMP/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProtokollLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProtokollLogic"),
        .testTarget(name: "ProtokollLogicTests", dependencies: ["ProtokollLogic"])
    ]
)
EOF

swift test --package-path "$TMP"
```

- [ ] **Step 3: 写冒烟测试**

创建 `ProtokollTests/SmokeTests.swift`：

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testHarnessRuns() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: 修改 CI 工作流**

在 `.github/workflows/ios-build.yml` 顶部改为：

```yaml
on:
  workflow_dispatch:
    inputs:
      include_model:
        description: "Device IPA 是否下载并打包约 0.9GB 的 Qwen3 模型"
        type: boolean
        default: true
  push:
    branches: [main, "feature/**"]
```

在 `jobs:` 下、`simulator-app` 之前新增 job：

```yaml
  logic-tests:
    name: Logic tests
    runs-on: macos-15
    timeout-minutes: 15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run logic tests
        run: bash tools/run-logic-tests.sh
```

给 `offline-ipa` job 增加条件（`name:` 下方）：

```yaml
    if: github.event_name == 'workflow_dispatch' || github.ref == 'refs/heads/main'
```

- [ ] **Step 5: 提交并验证（红→绿不需要，本任务只验证基础设施）**

```bash
git add tools/run-logic-tests.sh ProtokollTests/SmokeTests.swift .github/workflows/ios-build.yml
git commit -m "Add fast logic-test CI harness"
git push -u origin feature/german-protokoll
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: `Logic tests` PASS，`Simulator app for Appetize` PASS，`offline-ipa` SKIPPED。

---

### Task 2: 德语格式化（TDD）

**Files:**
- Modify: `AsrRecognize/Utilities/Formatters.swift`
- Create: `ProtokollTests/AppFormatTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/AppFormatTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class AppFormatTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 14, _ min: Int = 30) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testMeetingDateIsGerman() {
        XCTAssertEqual(AppFormat.meetingDate.string(from: date(2026, 10, 31)), "31.10.2026, 14:30")
    }

    func testHeroDateIsGerman() {
        XCTAssertEqual(AppFormat.heroDate.string(from: date(2026, 10, 31)), "Samstag, 31. Oktober")
    }

    func testDurationGerman() {
        XCTAssertEqual(AppFormat.duration(45), "45 Sek.")
        XCTAssertEqual(AppFormat.duration(3_900), "1 Std. 5 Min.")
        XCTAssertEqual(AppFormat.duration(7_200), "2 Std.")
    }

    func testCharacterCountUsesGermanGrouping() {
        XCTAssertEqual(AppFormat.characterCount(1_234), "1.234 Zeichen")
        XCTAssertEqual(AppFormat.characterCount(0), "0 Zeichen")
    }

    func testWeekLabelIsISOWeek() {
        XCTAssertEqual(AppFormat.weekLabel(date(2026, 10, 31)), "KW 44")
    }

    func testDefaultTitle() {
        XCTAssertEqual(AppFormat.defaultTitle(for: date(2026, 10, 31)), "Protokoll vom 31.10.2026")
    }
}
```

- [ ] **Step 2: 推送验证失败**

```bash
git add ProtokollTests/AppFormatTests.swift
git commit -m "Add German format tests"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status || true
```

Expected: `Logic tests` FAIL（`AppFormat.duration` 返回中文、`heroDate` 中文）。

- [ ] **Step 3: 实现德语格式化**

完整替换 `AsrRecognize/Utilities/Formatters.swift`：

```swift
import Foundation

enum AppFormat {
    static let locale = Locale(identifier: "de_DE")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = locale
        calendar.timeZone = .current
        return calendar
    }()

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static let meetingDate = makeFormatter("dd.MM.yyyy, HH:mm")
    static let dayOnly = makeFormatter("dd.MM.yyyy")
    static let heroDate = makeFormatter("EEEE, d. MMMM")
    static let fileStamp = makeFormatter("yyyy-MM-dd")

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
            return "\(total) Sek."
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0, minutes > 0 {
            return "\(hours) Std. \(minutes) Min."
        }
        if hours > 0 {
            return "\(hours) Std."
        }
        return "\(minutes) Min."
    }

    static func characterCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(number) Zeichen"
    }

    static func weekLabel(_ date: Date) -> String {
        "KW \(calendar.component(.weekOfYear, from: date))"
    }

    static func defaultTitle(for date: Date) -> String {
        "Protokoll vom \(dayOnly.string(from: date))"
    }
}
```

- [ ] **Step 4: 推送验证通过**

```bash
git add AsrRecognize/Utilities/Formatters.swift
git commit -m "Localize formatting to German conventions"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: `Logic tests` PASS；模拟器构建 PASS（`AppFormat` 保留了 `meetingDate`、`dayOnly`、`heroDate`、`clock`、`duration`、`defaultTitle` 的原有签名，现有视图仍可编译）。

---

### Task 3: 识别语言、Meeting 来源与导入存储基础

**Files:**
- Create: `AsrRecognize/Models/MeetingSource.swift`
- Create: `AsrRecognize/Services/RecognitionLanguage.swift`
- Modify: `AsrRecognize/Models/Meeting.swift`
- Modify: `AsrRecognize/Services/AudioStorage.swift`
- Modify: `AsrRecognize/Services/AppSettings.swift`
- Modify: `AsrRecognize/Services/LocalTranscriber.swift:419-421`
- Create: `ProtokollTests/RecognitionLanguageTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/RecognitionLanguageTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class RecognitionLanguageTests: XCTestCase {
    func testGermanMapping() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "de-DE"), "german")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "de-DE"), "de-DE")
    }

    func testEnglishMapping() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "en-US"), "english")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "en-US"), "en-US")
    }

    func testUnknownFallsBackToGerman() {
        XCTAssertEqual(RecognitionLanguage.qwenHint(for: "zh-CN"), "german")
        XCTAssertEqual(RecognitionLanguage.appleLocale(for: "zh-CN"), "de-DE")
    }
}
```

- [ ] **Step 2: 提交失败测试（预期 Logic tests 失败：类型不存在）**

```bash
git add ProtokollTests/RecognitionLanguageTests.swift
git commit -m "Add recognition language tests"
git push
```

- [ ] **Step 3: 实现 `RecognitionLanguage`**

创建 `AsrRecognize/Services/RecognitionLanguage.swift`：

```swift
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
```

- [ ] **Step 4: 实现 `MeetingSource` 与 Meeting 新字段**

创建 `AsrRecognize/Models/MeetingSource.swift`：

```swift
import Foundation

enum MeetingSource: String, Codable {
    case recording
    case import
}
```

完整替换 `AsrRecognize/Models/Meeting.swift`：

```swift
import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var segmentsData: Data
    var summaryData: Data?
    var audioFileName: String?
    var sourceRaw: String = MeetingSource.recording.rawValue
    var originalFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        transcript: String,
        segments: [TranscriptSegment] = [],
        audioFileName: String? = nil,
        source: MeetingSource = .recording,
        originalFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.segmentsData = (try? JSONEncoder().encode(segments)) ?? Data()
        self.summaryData = nil
        self.audioFileName = audioFileName
        self.sourceRaw = source.rawValue
        self.originalFileName = originalFileName
    }

    var source: MeetingSource {
        MeetingSource(rawValue: sourceRaw) ?? .recording
    }

    var segments: [TranscriptSegment] {
        (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
    }

    var summary: MeetingSummary? {
        get {
            guard let summaryData else { return nil }
            return try? JSONDecoder().decode(MeetingSummary.self, from: summaryData)
        }
        set {
            summaryData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var audioURL: URL? {
        guard let audioFileName, !audioFileName.isEmpty else { return nil }
        let url = AudioStorage.url(for: audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var snippet: String {
        let cleaned = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Kein Transkript vorhanden" : String(cleaned.prefix(90))
    }

    var hasSummary: Bool {
        guard let summary else { return false }
        return !summary.isEmpty
    }
}
```

- [ ] **Step 5: AudioStorage 支持导入扩展名**

在 `AsrRecognize/Services/AudioStorage.swift` 的 `makeNewFileURL()` 之后加入：

```swift
    static func makeImportedFileURL(extension ext: String) -> URL {
        let suffix = ext.isEmpty ? "audio" : ext.lowercased()
        return directory.appendingPathComponent("\(UUID().uuidString).\(suffix)")
    }
```

- [ ] **Step 6: AppSettings 默认德语与迁移**

修改 `AsrRecognize/Services/AppSettings.swift` 的 `init()` 与 `languageTitle`：

```swift
    init() {
        apiKey = KeychainStore.read(Keys.apiKey)
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
    }

    var languageTitle: String {
        RecognitionLanguage.title(for: languageCode)
    }
```

- [ ] **Step 7: 让 LocalTranscriber 使用共享语言映射**

把 `AsrRecognize/Services/Qwen3/LocalTranscriber.swift` 中的：

```swift
    private static func languageHint(for code: String) -> String {
        code.hasPrefix("zh") ? "chinese" : "english"
    }
```

替换为：

```swift
    private static func languageHint(for code: String) -> String {
        RecognitionLanguage.qwenHint(for: code)
    }
```

- [ ] **Step 8: 重新生成工程、提交并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize/Models/MeetingSource.swift AsrRecognize/Services/RecognitionLanguage.swift \
  AsrRecognize/Models/Meeting.swift AsrRecognize/Services/AudioStorage.swift \
  AsrRecognize/Services/AppSettings.swift AsrRecognize/Services/Qwen3/LocalTranscriber.swift \
  AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add German language defaults and meeting source metadata"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: `Logic tests` PASS。

---

### Task 4: 现有界面与服务全量德语化

**Files:**
- Modify: `AsrRecognize/Views/HomeView.swift`
- Modify: `AsrRecognize/Views/RecordingView.swift`
- Modify: `AsrRecognize/Views/SettingsView.swift`
- Modify: `AsrRecognize/Views/MeetingDetailView.swift`
- Modify: `AsrRecognize/Views/SummaryContentView.swift`
- Modify: `AsrRecognize/Services/LiveTranscriber.swift`
- Modify: `AsrRecognize/Services/Qwen3/LocalTranscriber.swift`
- Modify: `AsrRecognize/Services/Qwen3/ChunkTranscriptionEngine.swift`
- Modify: `AsrRecognize/Services/Qwen3/Qwen3CoreMLEngine.swift`
- Modify: `AsrRecognize/Services/Qwen3/Audio16kConverter.swift`（注释）
- Modify: `AsrRecognize/Services/Qwen3/AudioFileSink.swift`（注释）
- Modify: `AsrRecognize/Services/Qwen3/VoiceActivityDetector.swift`（注释）
- Modify: `AsrRecognize/Info.plist`
- Modify: `tools/generate_xcodeproj.py`

- [ ] **Step 1: 首页文案**

`HomeView.swift` 逐项替换（保持布局不变）：

| 原文 | 德语 |
| --- | --- |
| `设置` / `完成设置` | `Einstellungen` |
| `会议纪要` | `Protokolle` |
| `\(meetings.count) 场记录` | `\(meetings.count) Besprechungen` |
| `搜索会议、转写文字…` | `Protokolle und Transkripte durchsuchen…` |
| `清除搜索` | `Suche löschen` |
| `本周会议` | `Diese Woche` |
| `本周时长` | `Dauer diese Woche` |
| `全部记录` | `Gesamt` |
| `最近会议` / `搜索结果` | `Letzte Besprechungen` / `Suchergebnisse` |
| `还没有会议记录` | `Noch keine Protokolle` |
| `没有找到相关内容` | `Keine Treffer` |
| `点击下方按钮开始第一场录音，\n语音会实时转写为文字。` | `Tippen Sie unten auf „Aufnahme starten“, um Ihre erste Besprechung aufzunehmen.` |
| `换一个关键词试试，或清空搜索。` | `Versuchen Sie einen anderen Begriff oder leeren Sie die Suche.` |
| `删除` / `取消` | `Löschen` / `Abbrechen` |
| `删除这场会议？` | `Besprechung löschen?` |
| `「\(meeting.title)」的转写、纪要和录音将被永久删除。` | `Transkript, Protokoll und Aufnahme von „\(meeting.title)“ werden dauerhaft gelöscht.` |
| `开始记录` / `开始记录会议` | `Aufnahme starten` |
| `音频仅保存在本机 · \(settings.languageTitle)实时转写` | `Audio bleibt auf dem Gerät · Live-Transkript (\(settings.languageTitle))` |
| `音频` | `Audio` |
| `\(meeting.transcript.count) 字` | `AppFormat.characterCount(meeting.transcript.count)` |
| `暂无转写文本`（Meeting.swift） | `Kein Transkript vorhanden` |

首页 hero 行改为三部分：`AppFormat.heroDate`、`AppFormat.weekLabel(Date())`、`"\(meetings.count) Besprechungen"`。`weekDurationText` 改为 `AppFormat.duration(total)`。

同时新增导入入口的状态（本任务只加按钮与空动作，Task 12 接逻辑）：

```swift
    @State private var showImporter = false
```

在 `recordBar` 的 VStack 内、主按钮之前加入：

```swift
            Button {
                Haptics.tap()
                showImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Audiodatei importieren")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Audiodatei importieren")
```

- [ ] **Step 2: 录音页文案**

`RecordingView.swift` 替换：

| 原文 | 德语 |
| --- | --- |
| `没有识别到内容` | `Keine Sprache erkannt` |
| `继续记录` | `Weiter aufnehmen` |
| `放弃本次` | `Verwerfen` |
| `麦克风没有捕捉到可用的语音，请靠近麦克风再试。` | `Das Mikrofon hat keine verwertbare Sprache aufgenommen. Bitte näher am Mikrofon sprechen.` |
| `结束本次记录？` | `Aufnahme beenden?` |
| `保存并退出` | `Speichern & schließen` |
| `放弃并退出` | `Verwerfen` |
| `保存后会出现在会议列表中。` | `Die Aufnahme erscheint anschließend in der Liste.` |
| `关闭` / `结束并保存` | `Schließen` / `Beenden & speichern` |
| `完成` | `Fertig` |
| `PAUSED` / `STANDBY` | `PAUSIERT` / `BEREIT` |
| `实时转写` | `Live-Transkript` |
| `\(segments.count) 段` | `\(segments.count) Abschnitte` |
| `开始说话，文字会实时出现在这里…` | `Sprechen Sie, der Text erscheint hier live…` |
| `继续录音` / `暂停录音` | `Aufnahme fortsetzen` / `Aufnahme pausieren` |
| `正在准备麦克风…` | `Mikrofon wird vorbereitet…` |
| `正在加载本地模型…` | `Lokales Modell wird geladen…` |
| `首次使用需要授权麦克风与语音识别` | `Beim ersten Start werden Mikrofon- und Spracherkennungszugriff angefragt.` |
| `无法开始录音` | `Aufnahme konnte nicht gestartet werden` |
| `已保留 \(segments.count) 段转写内容` | `\(segments.count) Abschnitte des Transkripts wurden gesichert.` |
| `保存已有内容` | `Vorhandenes Transkript speichern` |
| `改用系统语音识别` | `System-Spracherkennung verwenden` |
| `重试` | `Erneut versuchen` |
| `打开系统设置` | `iOS-Einstellungen öffnen` |
| `本地 · 收尾中` | `Lokal · Abschluss läuft` |
| `中文 · 本地 Qwen3` | `Deutsch · Qwen3` |
| `ENGLISH · QWEN3` | `ENGLISH · QWEN3`（保留） |
| `中文 · 离线识别` / `中文 · 实时转写` | `Deutsch · Offline` / `Deutsch · Live` |
| `ENGLISH · OFFLINE` / `ENGLISH · LIVE` | 保留 |

识别标签逻辑改为使用 `settings.languageCode.hasPrefix("en")` 判断英语。

- [ ] **Step 3: 设置页文案**

`SettingsView.swift` 替换（AI 区块本任务只翻译现有 DeepSeek 字段，Task 5 再改结构）：

| 原文 | 德语 |
| --- | --- |
| `设置` / `完成` / `完成设置` | `Einstellungen` / `Fertig` / `Einstellungen schließen` |
| `DEEPSEEK` | `KI-ANBIETER`（Task 5 会再扩展） |
| `获取` | `Öffnen` |
| `保存 API Key` | `API-Schlüssel speichern` |
| `密钥仅保存在本机钥匙串。生成纪要时，转写文本会发送到 DeepSeek。` | `Der Schlüssel wird ausschließlich im Schlüsselbund gespeichert. Bei der KI-Zusammenfassung wird das Transkript an den konfigurierten Anbieter gesendet.` |
| `AI 纪要` | `KI-PROTOKOLL` |
| `自动生成纪要` | `Automatisch zusammenfassen` |
| `录音结束后自动调用 DeepSeek` | `Nach der Transkription automatisch zusammenfassen` |
| `模型` | `Modell` |
| `语音识别` | `SPRACHERKENNUNG` |
| `识别引擎` / `系统语音` / `本地 Qwen3` | `Spracherkennung` / `System-Spracherkennung` / `Lokales Qwen3` |
| `识别语言` / `中文` / `English` | `Sprache` / `Deutsch` / `English` |
| `仅设备端识别` | `Nur auf dem Gerät` |
| `音频不离开设备，准确率可能略低` | `Audio verlässt das Gerät nicht. Die Genauigkeit kann etwas geringer sein.` |
| `当前安装包未包含本地模型，录音时会提示并建议改用系统语音。` | `Diese App-Version enthält kein lokales Modell. Beim Start wird die System-Spracherkennung empfohlen.` |
| `完全离线，音频不出设备。模型约 0.9GB，首次加载约 1 分钟，仅支持 iOS 18 与真机。` | `Vollständig offline, Audio bleibt auf dem Gerät. Modell ca. 0,9 GB, erster Start ca. 1 Minute, nur iOS 18 und echtes Gerät.` |
| `使用 Apple Speech，可按「仅设备端识别」开关切换离线与否。` | `Verwendet Apple Speech. Mit „Nur auf dem Gerät“ kann offline erkannt werden.` |
| `关于` / `版本` | `ÜBER` / `Version` |
| `语音由 Apple Speech 实时转写，会议纪要由 DeepSeek 生成。音频与文字默认仅存储在本机。` | `Audio und Transkripte bleiben auf dem Gerät. Nur bei aktivierter KI-Zusammenfassung wird das Transkript an den eingestellten Anbieter gesendet.` |
| `本地优先 · 隐私可控` | `LOKAL ZUERST · DATENSCHUTZ` |
| `隐藏 API Key` / `显示 API Key` | `API-Schlüssel ausblenden` / `API-Schlüssel anzeigen` |
| `已保存` | `Gespeichert` |

- [ ] **Step 4: 详情页与纪要卡片文案**

`MeetingDetailView.swift` 替换：

| 原文 | 德语 |
| --- | --- |
| `AI 纪要` / `原文` | `Zusammenfassung` / `Transkript` |
| `删除这场会议？` / `删除` / `取消` | `Besprechung löschen?` / `Löschen` / `Abbrechen` |
| `转写、纪要与录音将被永久删除，无法恢复。` | `Transkript, Protokoll und Aufnahme werden dauerhaft gelöscht.` |
| `分享纪要` | `Protokoll teilen` |
| `复制原文` | `Transkript kopieren` |
| `重新生成纪要` | `Neu zusammenfassen` |
| `删除会议` | `Besprechung löschen` |
| `更多操作` / `返回` | `Weitere Aktionen` / `Zurück` |
| `会议标题` | `Titel der Besprechung` |
| `点击标题即可编辑` | `Tippen Sie auf den Titel, um ihn zu bearbeiten` |
| `\(meeting.transcript.count) 字` | `AppFormat.characterCount(meeting.transcript.count)` |
| `播放录音` / `暂停播放` | `Aufnahme abspielen` / `Wiedergabe pausieren` |
| `原始转写` / `复制` | `Transkript` / `Kopieren` |
| `复制转写原文` | `Transkript kopieren` |
| `已复制到剪贴板` | `In die Zwischenablage kopiert` |
| `请先在设置中填写 DeepSeek API Key。` | `Bitte hinterlegen Sie zuerst einen API-Schlüssel in den Einstellungen.` |
| `这场会议还没有转写内容。` | `Für diese Besprechung liegt noch kein Transkript vor.` |

`shareText` 的 Markdown 标题改为 `Datum: … · Dauer: …`、`## Zusammenfassung`、`## Kernpunkte`、`## Aufgaben`、`Verantwortlich: …`、`Frist: …`、`## Beschlüsse`、`## Transkript`。

`SummaryContentView.swift` 替换：

| 原文 | 德语 |
| --- | --- |
| `会议摘要` / `关键要点` / `待办事项` / `会议决议` | `Zusammenfassung` / `Kernpunkte` / `Aufgaben` / `Beschlüsse` |
| `负责人 · \(owner)` / `截止 · \(deadline)` | `Verantwortlich · \(owner)` / `Frist · \(deadline)` |
| `转写内容较长，本次仅分析前 2 万字。` | `Das Transkript wurde für die Zusammenfassung gekürzt.` |
| `AI 会议纪要` / `由 DeepSeek 提炼` | `KI-Protokoll` / `Erstellt mit DeepSeek`（Task 5 改为 `settings.aiModel`） |
| `DEEPSEEK` | 暂时保留，Task 5 改为 `settings.aiModel.uppercased()` |
| `AI 正在整理纪要…` / `通常需要 10–30 秒` | `Die KI erstellt das Protokoll…` / `Meist dauert das 10–30 Sekunden.` |
| `纪要生成失败` / `重试` / `检查设置` | `Protokoll konnte nicht erstellt werden` / `Erneut versuchen` / `Einstellungen prüfen` |
| `连接 DeepSeek` / `开启 AI 纪要` | `KI-Protokoll einrichten` / `Automatische Zusammenfassung aktivieren` |
| `填写 API Key 后，转写文本会发送给 DeepSeek，自动提炼摘要、关键要点与待办事项。` | `Hinterlegen Sie einen API-Schlüssel. Das Transkript wird dann an den eingestellten Anbieter gesendet und zu einem Protokoll zusammengefasst.` |
| `配置 API Key` | `API-Schlüssel hinterlegen` |
| `生成 AI 会议纪要` / `摘要 · 要点 · 待办 · 决议` | `KI-Protokoll erstellen` / `Zusammenfassung · Kernpunkte · Aufgaben · Beschlüsse` |
| `基于本次会议的转写内容，由 DeepSeek 提炼结构化纪要。` | `Erstellt aus dem Transkript ein strukturiertes Protokoll.` |
| `生成纪要` | `Protokoll erstellen` |

- [ ] **Step 5: 服务层与引擎错误文案**

`LiveTranscriber.swift`：

```swift
enum TranscriberError: LocalizedError {
    case noInput
    var errorDescription: String? { "Kein Mikrofoneingang gefunden." }
}
```

并替换字符串：

- `未获得语音识别权限。…` → `Kein Zugriff auf die Spracherkennung. Bitte in den iOS-Einstellungen unter „Datenschutz & Sicherheit › Spracherkennung“ aktivieren.`
- `未获得麦克风权限。…` → `Kein Zugriff auf das Mikrofon. Bitte in den iOS-Einstellungen unter „Datenschutz & Sicherheit › Mikrofon“ aktivieren.`
- `当前语言暂不支持语音识别。` → `Für diese Sprache ist keine Spracherkennung verfügbar.`
- `语音识别服务暂不可用，请检查网络后重试。` → `Die Spracherkennung ist derzeit nicht verfügbar. Bitte prüfen Sie Ihre Internetverbindung.`
- `无法开始录音：\(...)` → `Aufnahme konnte nicht gestartet werden: \(...)`
- `无法恢复录音：\(...)` → `Aufnahme konnte nicht fortgesetzt werden: \(...)`
- `语音识别中断：\(...)` → `Spracherkennung unterbrochen: \(...)`

`LocalTranscriber.swift`：

- `本地模型未加载` → `Lokales Modell nicht geladen`
- `未获得麦克风权限。…` → 同上麦克风文案
- `无法开始录音：\(...)` / `无法恢复录音：\(...)` → 同上
- `模型未打包` → `Modell nicht enthalten`
- `当前安装包里没有本地 Qwen3 模型，请改用系统语音识别。` → `In dieser App-Version ist kein lokales Qwen3-Modell enthalten. Bitte verwenden Sie die System-Spracherkennung.`
- `首次加载模型可能较慢…` → `Der erste Modellstart kann etwas dauern…`
- `模型就绪` → `Modell bereit`
- `模型不可用` → `Modell nicht verfügbar`
- `本地模型加载失败：\(...)` → `Lokales Modell konnte nicht geladen werden: \(...)`
- `识别失败：\(...)` → `Erkennung fehlgeschlagen: \(...)`
- `内存紧张，模型已释放` → `Speicher knapp – Modell wurde entladen.`
- `没有检测到可用的麦克风输入` → `Kein Mikrofoneingang gefunden.`

`ChunkTranscriptionEngine.swift`：

```swift
    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Das lokale Modell ist noch nicht bereit."
        case .modelMissing:
            return "Das lokale Qwen3-Modell ist in dieser App-Version nicht enthalten."
        case .emptyResult:
            return "Die lokale Erkennung hat keinen Text geliefert."
        }
    }
```

`Qwen3CoreMLEngine.swift`：

- `本地 Qwen3-ASR（Core ML）` → `Lokales Qwen3-ASR (Core ML)`
- `读取本地模型…` → `Lokales Modell wird gelesen…`
- `预热模型…` → `Modell wird vorbereitet…`
- `模型就绪` → `Modell bereit`

三个 Qwen3 工具文件中的中文注释改成等价英文注释（只改注释，不改逻辑）。

- [ ] **Step 6: Info.plist**

完整替换 `AsrRecognize/Info.plist` 中相关键：

```xml
	<key>CFBundleDevelopmentRegion</key>
	<string>de</string>
	<key>CFBundleDisplayName</key>
	<string>Protokoll</string>
```

新增：

```xml
	<key>CFBundleLocalizations</key>
	<array>
		<string>de</string>
	</array>
```

权限说明：

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Protokoll benötigt Zugriff auf das Mikrofon, um Besprechungen aufzunehmen und zu transkribieren.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Protokoll wandelt Ihre Aufnahmen in Text um, um daraus ein Protokoll zu erstellen.</string>
```

- [ ] **Step 6b: 工程级本地化**

在 `tools/generate_xcodeproj.py` 中把：

```python
        "\t\t\tdevelopmentRegion = en;\n"
```

改为：

```python
        "\t\t\tdevelopmentRegion = de;\n"
```

把：

```python
        "\t\t\tknownRegions = (\n"
        "\t\t\t\ten,\n"
        "\t\t\t\tBase,\n"
        "\t\t\t\t\"zh-Hans\",\n"
        "\t\t\t);\n"
```

改为：

```python
        "\t\t\tknownRegions = (\n"
        "\t\t\t\tde,\n"
        "\t\t\t\tBase,\n"
        "\t\t\t);\n"
```

- [ ] **Step 7: 检查无中文残留并提交**

```bash
python - <<'EOF'
import re, pathlib, sys
bad = []
for p in pathlib.Path('AsrRecognize').rglob('*'):
    if p.suffix not in {'.swift', '.plist'}:
        continue
    # DeepSeekService.swift 在 Task 5 被删除，本任务暂不要求它清零
    if p.name == 'DeepSeekService.swift':
        continue
    for i, line in enumerate(p.read_text(encoding='utf-8').splitlines(), 1):
        if re.search(r'[一-鿿]', line):
            bad.append(f"{p}:{i}: {line.strip()}")
if bad:
    print("\n".join(bad))
    sys.exit(1)
print("OK: no CJK characters")
EOF
```

Expected: `OK: no CJK characters`。

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize
git commit -m "Localize app UI and errors to German"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: `Logic tests` 与模拟器构建 PASS。

---

### Task 5: 自定义 OpenAI 兼容 AI 纪要（TDD）

**Files:**
- Create: `AsrRecognize/Services/AISummaryRequest.swift`
- Create: `AsrRecognize/Services/AISummaryService.swift`
- Delete: `AsrRecognize/Services/DeepSeekService.swift`
- Modify: `AsrRecognize/Services/AppSettings.swift`
- Modify: `AsrRecognize/Services/KeychainStore.swift`
- Modify: `AsrRecognize/Views/SettingsView.swift`
- Modify: `AsrRecognize/Views/SummaryContentView.swift`
- Modify: `AsrRecognize/Views/MeetingDetailView.swift`
- Create: `ProtokollTests/AISummaryRequestTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/AISummaryRequestTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class AISummaryRequestTests: XCTestCase {
    private let configuration = AIConfiguration(
        baseURL: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        apiKey: "test-key"
    )

    func testEndpointNormalization() throws {
        let url = try AISummaryRequest.endpointURL("https://api.openai.com/v1/")
        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testRejectsNonHTTPS() {
        XCTAssertThrowsError(try AISummaryRequest.endpointURL("http://example.com"))
        XCTAssertThrowsError(try AISummaryRequest.endpointURL("not a url"))
    }

    func testRequestContainsGermanPromptAndModel() throws {
        let request = try AISummaryRequest.make(configuration: configuration, transcript: "Hallo zusammen.")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.timeoutInterval, 180)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]!.contains("Protokollassistent"))
        XCTAssertTrue(messages[0]["content"]!.contains("Deutsch"))
        XCTAssertTrue(messages[1]["content"]!.contains("Hallo zusammen."))
    }

    func testTranscriptTruncation() throws {
        let long = String(repeating: "a", count: AISummaryRequest.maxCharacters + 10)
        let (text, truncated) = AISummaryRequest.trimmedTranscript(long)
        XCTAssertTrue(truncated)
        XCTAssertEqual(text.count, AISummaryRequest.maxCharacters)
    }

    func testParseSummary() throws {
        let content = """
        {"overview":"Kurz","keyPoints":["A"],"actionItems":[{"task":"T","owner":"Max","deadline":"Freitag"}],"decisions":["D"]}
        """
        let summary = try AISummaryRequest.parse(content: content)
        XCTAssertEqual(summary.overview, "Kurz")
        XCTAssertEqual(summary.actionItems.first?.owner, "Max")
    }
}
```

- [ ] **Step 2: 提交失败测试**

```bash
git add ProtokollTests/AISummaryRequestTests.swift
git commit -m "Add AI request tests"
git push
```

Expected: Logic tests FAIL（`AIConfiguration` 不存在）。

- [ ] **Step 3: 实现纯请求逻辑**

创建 `AsrRecognize/Services/AISummaryRequest.swift`：

```swift
import Foundation

struct AIConfiguration: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

enum AISummaryError: LocalizedError {
    case invalidURL
    case missingKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die Basis-URL ist ungültig. Bitte eine https://-Adresse eingeben."
        case .missingKey:
            return "Es ist kein API-Schlüssel hinterlegt."
        case .invalidResponse:
            return "Die Antwort der KI konnte nicht verarbeitet werden."
        case .server(let message):
            return message
        }
    }
}

enum AISummaryRequest {
    static let maxCharacters = 120_000

    static let systemPrompt = """
    Sie sind ein erfahrener Protokollassistent. Erstellen Sie aus dem bereitgestellten Transkript ein strukturiertes Besprechungsprotokoll.
    Geben Sie ausschließlich JSON aus, ohne Markdown-Codeblöcke oder Erklärungen. Struktur:
    {"overview":"Zusammenfassung in 100 bis 200 Wörtern","keyPoints":["Kernpunkt"],"actionItems":[{"task":"Aufgabe","owner":"Verantwortlich oder leer","deadline":"Frist oder leer"}],"decisions":["Beschluss"]}
    Anforderungen:
    1. Verwenden Sie ausschließlich Informationen aus dem Transkript. Erfinden Sie keine Fakten, Namen oder Zahlen.
    2. Antworten Sie vollständig auf Deutsch.
    3. Aufgaben müssen konkret und umsetzbar sein, maximal 8.
    4. Wenn eine Kategorie im Transkript fehlt, geben Sie ein leeres Array zurück.
    """

    static func normalizedBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func endpointURL(_ raw: String) throws -> URL {
        let base = normalizedBaseURL(raw)
        guard let components = URLComponents(string: base),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            throw AISummaryError.invalidURL
        }
        guard let url = URL(string: base + "/chat/completions") else {
            throw AISummaryError.invalidURL
        }
        return url
    }

    static func trimmedTranscript(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > maxCharacters else { return (text, false) }
        return (String(text.prefix(maxCharacters)), true)
    }

    static func make(configuration: AIConfiguration, transcript: String) throws -> URLRequest {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AISummaryError.missingKey }

        let url = try endpointURL(configuration.baseURL)
        let source = trimmedTranscript(transcript).text

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Transkript der Besprechung:\n\(source)"]
            ],
            "temperature": 0.2,
            "max_tokens": 2000,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(content: String) throws -> MeetingSummary {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end {
            cleaned = String(cleaned[start...end])
        }
        if let data = cleaned.data(using: .utf8),
           let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data),
           !summary.isEmpty {
            return summary
        }
        let fallback = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { throw AISummaryError.invalidResponse }
        return MeetingSummary(overview: fallback)
    }
}
```

- [ ] **Step 4: 实现网络服务并删除旧文件**

创建 `AsrRecognize/Services/AISummaryService.swift`：

```swift
import Foundation

enum AISummaryService {
    static func summarize(
        transcript: String,
        configuration: AIConfiguration,
        session: URLSession = .shared
    ) async throws -> MeetingSummary {
        let request = try AISummaryRequest.make(configuration: configuration, transcript: transcript)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AISummaryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw AISummaryError.server(envelope.error.message)
            }
            throw AISummaryError.server("Die KI-Anfrage ist fehlgeschlagen (HTTP \(http.statusCode)).")
        }

        let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw AISummaryError.invalidResponse
        }
        return try AISummaryRequest.parse(content: content)
    }

    private struct ChatEnvelope: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    private struct APIErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable { let message: String }
    }
}
```

```bash
git rm AsrRecognize/Services/DeepSeekService.swift
```

- [ ] **Step 5: Keychain 支持删除**

在 `KeychainStore.swift` 加入：

```swift
    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
```

- [ ] **Step 6: AppSettings 增加 AI 配置**

在 `AppSettings.swift` 中新增键与属性（保留现有 `apiKey` 名称，但改为按端点存储）：

```swift
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

    static func keychainAccount(for baseURL: String) -> String {
        "ai-key:" + AISummaryRequest.normalizedBaseURL(baseURL)
    }
```

在 `init()` 中（语言与引擎初始化之后）：

```swift
        aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? Self.defaultBaseURL
        aiModel = defaults.string(forKey: Keys.aiModel) ?? Self.defaultModel

        let legacyKey = KeychainStore.read(Keys.apiKey)
        if !legacyKey.isEmpty {
            let account = Self.keychainAccount(for: aiBaseURL)
            if KeychainStore.read(account).isEmpty {
                KeychainStore.save(legacyKey, for: account)
            }
            KeychainStore.delete(Keys.apiKey)
        }
        apiKey = KeychainStore.read(Self.keychainAccount(for: aiBaseURL))
```

增加：

```swift
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
```

注意：`init()` 中要先给 `aiBaseURL`、`aiModel`、`apiKey` 赋值，再使用 didSet 属性；Swift 初始化顺序按上面写法即可（属性都有初始赋值）。

同时删除 `AppSettings` 中旧的 `let model = "deepseek-chat"`，并把 `SettingsView.swift` 第 195 行附近的 `Text(settings.model)` 改为 `Text(settings.aiModel)`。

- [ ] **Step 7: 设置页 AI 区块改造**

把 `SettingsView.swift` 的 `apiSection` 替换为（保留 `glassCard()`）：

```swift
    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "KI-ANBIETER")

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Basis-URL", text: $draftBaseURL, placeholder: "https://api.openai.com/v1", secure: false)
                labeledField("Modell", text: $draftModel, placeholder: "gpt-4o-mini", secure: false)
                labeledField("API-Schlüssel", text: $draftKey, placeholder: "sk-…", secure: !keyVisible)

                if let aiError {
                    Text(aiError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.record)
                }

                PillButton(title: "Speichern", icon: "checkmark") {
                    saveAI()
                }

                Text("Der Schlüssel wird im Schlüsselbund gespeichert. Bei der KI-Zusammenfassung wird ausschließlich das Transkript an diesen Anbieter gesendet.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)
            }
            .glassCard()
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
```

新增状态与保存逻辑：

```swift
    @State private var draftBaseURL = ""
    @State private var draftModel = ""
    @State private var draftKey = ""
    @State private var aiError: String?
```

`onAppear` 中：

```swift
            draftBaseURL = settings.aiBaseURL
            draftModel = settings.aiModel
            draftKey = settings.apiKey
```

替换 `saveKey()` 为：

```swift
    private func saveAI() {
        do {
            try settings.applyAIConfiguration(baseURL: draftBaseURL, model: draftModel, key: draftKey)
            draftBaseURL = settings.aiBaseURL
            draftModel = settings.aiModel
            aiError = nil
            Haptics.success()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                savedFlash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    savedFlash = false
                }
            }
        } catch {
            aiError = error.localizedDescription
            Haptics.warning()
        }
    }
```

同时删除旧的 “获取” 链接与 `saveKey()`，并确保 `summarySection` 的模型行显示 `settings.aiModel`。

- [ ] **Step 8: 详情页与纪要卡片接入新服务**

`MeetingDetailView.generateSummary()` 中：

```swift
        do {
            let result = try await AISummaryService.summarize(
                transcript: transcript,
                configuration: settings.aiConfiguration
            )
            meeting.summary = result
            try? modelContext.save()
            Haptics.success()
        } catch {
            summaryError = error.localizedDescription
            Haptics.warning()
        }
```

`SummaryContentView` 增加：

```swift
    @EnvironmentObject private var settings: AppSettings
```

把 `StatusPill(text: "DEEPSEEK", ...)` 改为 `StatusPill(text: settings.aiModel.uppercased(), ...)`，把 `由 DeepSeek 提炼` 改为 `Erstellt mit \(settings.aiModel)`。

把 `MeetingDetailView.summarySection` 中的 `truncated: meeting.transcript.count > 20000` 改为 `truncated: meeting.transcript.count > AISummaryRequest.maxCharacters`。

- [ ] **Step 9: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize ProtokollTests AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add configurable OpenAI-compatible AI summaries"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: Logic tests PASS；模拟器构建 PASS。

**实现偏差记录：**
- 网络错误统一映射为德语 `AISummaryError.network`；响应解码失败映射为 `.invalidResponse`。
- `ChatEnvelope.Message.content` 改为 `String?`，nil/空视为 `.invalidResponse`。
- 端点切换时的 Key 规则：仅当用户输入的新 Key 与旧端点 Key 不同才写入新端点；否则保留目标端点已存的 Key（同端点时以输入为准）。

---

### Task 6: 导出服务与详情页导出入口（TDD）

**Files:**
- Create: `AsrRecognize/Services/ExportService.swift`
- Create: `AsrRecognize/Views/ActivityView.swift`
- Modify: `AsrRecognize/Views/MeetingDetailView.swift`
- Create: `ProtokollTests/ExportServiceTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/ExportServiceTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class ExportServiceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    func testSanitizeKeepsUmlautsAndRemovesIllegalCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("Besprechung: Q4/Plan? äöü"), "Besprechung- Q4-Plan- äöü")
        XCTAssertEqual(FilenameSanitizer.sanitize("   ...   "), "Protokoll")
        XCTAssertEqual(FilenameSanitizer.sanitize(String(repeating: "a", count: 80)).count, 60)
    }

    func testTextWithoutSummary() {
        let payload = ExportPayload(
            title: "Teamrunde",
            date: date,
            duration: 3_900,
            transcript: "Guten Tag.",
            summary: nil
        )
        let text = ExportService.text(for: payload)
        XCTAssertTrue(text.contains("Datum:"))
        XCTAssertTrue(text.contains("Dauer: 1 Std. 5 Min."))
        XCTAssertTrue(text.contains("## Transkript\nGuten Tag."))
        XCTAssertFalse(text.contains("## Zusammenfassung"))
    }

    func testTextWithSummary() {
        let summary = MeetingSummary(
            overview: "Kurz",
            keyPoints: ["A", "B"],
            actionItems: [ActionItem(task: "Liefern", owner: "Max", deadline: "Freitag")],
            decisions: ["Freigabe erteilt"]
        )
        let payload = ExportPayload(title: "Planung", date: date, duration: 60, transcript: "Text.", summary: summary)
        let text = ExportService.text(for: payload)
        XCTAssertTrue(text.contains("## Zusammenfassung\nKurz"))
        XCTAssertTrue(text.contains("- Liefern · Verantwortlich: Max · Frist: Freitag"))
        XCTAssertTrue(text.contains("## Beschlüsse\n- Freigabe erteilt"))
    }
}
```

- [ ] **Step 2: 提交失败测试并确认 Logic tests 失败**

```bash
git add ProtokollTests/ExportServiceTests.swift
git commit -m "Add export tests"
git push
```

- [ ] **Step 3: 实现导出服务**

创建 `AsrRecognize/Services/ExportService.swift`：

```swift
import Foundation

struct ExportPayload {
    var title: String
    var date: Date
    var duration: TimeInterval
    var transcript: String
    var summary: MeetingSummary?
}

enum FilenameSanitizer {
    static func sanitize(_ raw: String, fallback: String = "Protokoll") -> String {
        var value = raw.replacingOccurrences(
            of: "[/\\\\:*?\"<>|\\n\\r\\t]",
            with: "-",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        if value.count > 60 {
            value = String(value.prefix(60))
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        }
        return value.isEmpty ? fallback : value
    }
}

enum ExportService {
    static func text(for payload: ExportPayload) -> String {
        var lines: [String] = []
        lines.append(payload.title)
        lines.append("")
        lines.append("Datum: \(AppFormat.meetingDate.string(from: payload.date))")
        lines.append("Dauer: \(AppFormat.duration(payload.duration))")
        lines.append("")

        if let summary = payload.summary, !summary.isEmpty {
            if !summary.overview.isEmpty {
                lines.append("## Zusammenfassung")
                lines.append(summary.overview)
                lines.append("")
            }
            if !summary.keyPoints.isEmpty {
                lines.append("## Kernpunkte")
                lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
                lines.append("")
            }
            if !summary.actionItems.isEmpty {
                lines.append("## Aufgaben")
                for item in summary.actionItems {
                    var parts = [item.task]
                    if let owner = item.owner, !owner.isEmpty {
                        parts.append("Verantwortlich: \(owner)")
                    }
                    if let deadline = item.deadline, !deadline.isEmpty {
                        parts.append("Frist: \(deadline)")
                    }
                    lines.append("- " + parts.joined(separator: " · "))
                }
                lines.append("")
            }
            if !summary.decisions.isEmpty {
                lines.append("## Beschlüsse")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
                lines.append("")
            }
        }

        lines.append("## Transkript")
        lines.append(payload.transcript)
        return lines.joined(separator: "\n")
    }

    static func writeText(for payload: ExportPayload) throws -> URL {
        let directory = try exportDirectory()
        let name = "Protokoll_\(FilenameSanitizer.sanitize(payload.title))_\(AppFormat.fileStamp.string(from: payload.date)).txt"
        let url = directory.appendingPathComponent(name)
        try text(for: payload).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func prepareAudio(source: URL, title: String) throws -> URL {
        let directory = try exportDirectory()
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let url = directory.appendingPathComponent("\(FilenameSanitizer.sanitize(title)).\(ext)")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try FileManager.default.linkItem(at: source, to: url)
        } catch {
            try FileManager.default.copyItem(at: source, to: url)
        }
        return url
    }

    private static func exportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
```

- [ ] **Step 4: 分享面板封装**

创建 `AsrRecognize/Views/ActivityView.swift`：

```swift
import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 5: 详情页接入导出**

`MeetingDetailView` 增加状态：

```swift
    @State private var exportItem: ExportItem?
    @State private var exportError: String?

    struct ExportItem: Identifiable {
        let id = UUID()
        let url: URL
    }
```

在 `topBar` 既有 Menu 的最上方加入导出子菜单：

```swift
                Menu {
                    Button {
                        exportText()
                    } label: {
                        Label("Als Text (.txt)", systemImage: "doc.text")
                    }
                    if meeting.audioURL != nil {
                        Button {
                            exportAudio()
                        } label: {
                            Label("Audio exportieren", systemImage: "waveform")
                        }
                        if audioFileSize > 500_000_000 {
                            Text("Bei großen Dateien kann der Export einige Sekunden dauern.")
                        }
                    }
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up.on.square")
                }
```

在 MeetingDetailView 中加入：

```swift
    private var audioFileSize: Int64 {
        guard let url = meeting.audioURL else { return 0 }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
```

在 body 的 `.sheet(isPresented: $showSettings)` 后追加：

```swift
        .sheet(item: $exportItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Export fehlgeschlagen", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
```

加入方法：

```swift
    private func exportText() {
        do {
            let payload = ExportPayload(
                title: meeting.title,
                date: meeting.createdAt,
                duration: meeting.duration,
                transcript: meeting.transcript,
                summary: meeting.summary
            )
            exportItem = ExportItem(url: try ExportService.writeText(for: payload))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportAudio() {
        guard let source = meeting.audioURL else { return }
        do {
            exportItem = ExportItem(url: try ExportService.prepareAudio(source: source, title: meeting.title))
        } catch {
            exportError = error.localizedDescription
        }
    }
```

- [ ] **Step 6: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize ProtokollTests AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add TXT and audio export"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: Logic tests PASS；模拟器构建 PASS。

---

### Task 7: 导入检查点存储（TDD）

**Files:**
- Create: `AsrRecognize/Services/ImportJobStore.swift`
- Create: `ProtokollTests/ImportJobStoreTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/ImportJobStoreTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class ImportJobStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ImportJobStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ImportJobStore(baseDirectory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeJob() -> ImportJob {
        ImportJob(
            id: UUID(),
            audioFileName: "audio.m4a",
            originalFileName: "Original.m4a",
            title: "Teamrunde",
            engine: "qwen",
            languageCode: "de-DE",
            offlineOnly: true,
            duration: 120,
            framesProcessed: 0,
            sourceSampleRate: 16_000,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_793_000_000)
        )
    }

    func testRoundTripAndAppend() async throws {
        let job = makeJob()
        try await store.create(job)
        let first = TranscriptSegment(text: "Hallo", timestamp: 1)
        let second = TranscriptSegment(text: "Welt", timestamp: 2)
        try await store.append(first, to: job.id)
        try await store.append(second, to: job.id)

        var updated = job
        updated.framesProcessed = 32_000
        try await store.update(updated)

        let loaded = await store.job(id: job.id)
        XCTAssertEqual(loaded?.framesProcessed, 32_000)
        let segments = await store.segments(for: job.id)
        XCTAssertEqual(segments.map(\.text), ["Hallo", "Welt"])
    }

    func testResumableJobsExcludeFinished() async throws {
        var running = makeJob()
        running.status = .running
        var finished = makeJob()
        finished.status = .finished
        try await store.create(running)
        try await store.create(finished)

        let jobs = await store.resumableJobs()
        XCTAssertEqual(jobs.map(\.id), [running.id])
    }

    func testDeleteRemovesDirectory() async throws {
        let job = makeJob()
        try await store.create(job)
        await store.delete(id: job.id)
        let jobs = await store.resumableJobs()
        XCTAssertTrue(jobs.isEmpty)
    }
}
```

- [ ] **Step 2: 提交失败测试**

```bash
git add ProtokollTests/ImportJobStoreTests.swift
git commit -m "Add import checkpoint tests"
git push
```

- [ ] **Step 3: 实现存储**

创建 `AsrRecognize/Services/ImportJobStore.swift`：

```swift
import Foundation

struct ImportJob: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case running
        case paused
        case finished
    }

    var id: UUID
    var audioFileName: String
    var originalFileName: String
    var title: String
    var engine: String
    var languageCode: String
    var offlineOnly: Bool
    var duration: TimeInterval
    var framesProcessed: Int64
    var sourceSampleRate: Double
    var status: Status
    var createdAt: Date
}

actor ImportJobStore {
    static let shared = ImportJobStore()

    private let base: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportJobs", isDirectory: true)
        base = root
    }

    private func directory(for id: UUID) -> URL {
        base.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func stateURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("state.json")
    }

    private func segmentsURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("segments.jsonl")
    }

    func create(_ job: ImportJob) throws {
        let dir = directory(for: job.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(job).write(to: stateURL(for: job.id), options: .atomic)
        FileManager.default.createFile(atPath: segmentsURL(for: job.id).path, contents: nil)
    }

    func update(_ job: ImportJob) throws {
        try FileManager.default.createDirectory(at: directory(for: job.id), withIntermediateDirectories: true)
        try encoder.encode(job).write(to: stateURL(for: job.id), options: .atomic)
    }

    func append(_ segment: TranscriptSegment, to id: UUID) throws {
        let url = segmentsURL(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try encoder.encode(segment)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func segments(for id: UUID) -> [TranscriptSegment] {
        guard let data = try? Data(contentsOf: segmentsURL(for: id)) else { return [] }
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(TranscriptSegment.self, from: Data(line))
        }
    }

    func job(id: UUID) -> ImportJob? {
        guard let data = try? Data(contentsOf: stateURL(for: id)) else { return nil }
        return try? decoder.decode(ImportJob.self, from: data)
    }

    func resumableJobs() -> [ImportJob] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("state.json")),
                  let job = try? decoder.decode(ImportJob.self, from: data),
                  job.status != .finished else { return nil }
            return job
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}
```

- [ ] **Step 4: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize ProtokollTests AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add resumable import job store"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: Logic tests PASS。

---

### Task 8: 导入校验（TDD）

**Files:**
- Create: `AsrRecognize/Services/ImportValidation.swift`
- Create: `ProtokollTests/ImportValidationTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `ProtokollTests/ImportValidationTests.swift`：

```swift
import XCTest
@testable import ProtokollLogic

final class ImportValidationTests: XCTestCase {
    func testAcceptsTwoHours() throws {
        XCTAssertNoThrow(try ImportValidation.validate(duration: 7_200, fileSize: 1_000_000))
    }

    func testRejectsTooLong() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 7_201, fileSize: 1_000_000)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .tooLong)
        }
    }

    func testRejectsTooLarge() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 60, fileSize: 1_500_000_001)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .tooLarge)
        }
    }

    func testRejectsInvalidDuration() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 0, fileSize: 1_000))
    }

    func testRejectsInsufficientSpace() {
        XCTAssertThrowsError(
            try ImportValidation.validateAvailableSpace(required: 2_000_000_000, available: 1_000_000_000)
        ) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .insufficientSpace)
        }
    }

    func testMissingSpaceInformationIsAccepted() {
        XCTAssertNoThrow(try ImportValidation.validateAvailableSpace(required: 2_000_000_000, available: nil))
    }
}
```

- [ ] **Step 2: 提交失败测试**

```bash
git add ProtokollTests/ImportValidationTests.swift
git commit -m "Add import validation tests"
git push
```

- [ ] **Step 3: 实现**

创建 `AsrRecognize/Services/ImportValidation.swift`：

```swift
import Foundation

enum ImportValidation {
    static let maxDuration: TimeInterval = 7_200
    static let maxFileSize: Int64 = 1_500_000_000

    enum Failure: LocalizedError, Equatable {
        case tooLong
        case tooLarge
        case invalid
        case insufficientSpace

        var errorDescription: String? {
            switch self {
            case .tooLong:
                return "Die Audiodatei ist länger als 2 Stunden."
            case .tooLarge:
                return "Die Audiodatei ist zu groß (maximal 1,5 GB)."
            case .invalid:
                return "Die Audiodatei konnte nicht gelesen werden."
            case .insufficientSpace:
                return "Nicht genügend Speicherplatz für die Audiodatei."
            }
        }
    }

    static func validate(duration: TimeInterval, fileSize: Int64) throws {
        guard duration > 0 else { throw Failure.invalid }
        guard duration <= maxDuration else { throw Failure.tooLong }
        guard fileSize <= maxFileSize else { throw Failure.tooLarge }
    }

    static func validateAvailableSpace(required: Int64, available: Int64?) throws {
        guard let available else { return }
        guard available >= required else { throw Failure.insufficientSpace }
    }
}
```

- [ ] **Step 4: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize ProtokollTests AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add audio import validation"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: Logic tests PASS。

---

### Task 9: Apple Speech 分段引擎

**Files:**
- Create: `AsrRecognize/Services/AppleChunkEngine.swift`
- Modify: `AsrRecognize/Services/Qwen3/ChunkTranscriptionEngine.swift`

- [ ] **Step 1: 扩展错误类型**

在 `ChunkTranscriptionEngine.swift` 的 `TranscriptionEngineError` 中加入：

```swift
    case permissionDenied
    case unsupportedLanguage
    case offlineUnavailable
    case serviceUnavailable
    case timeout
```

并补充德语 `errorDescription`：

```swift
        case .permissionDenied:
            return "Spracherkennung ist nicht erlaubt. Bitte in den iOS-Einstellungen aktivieren."
        case .unsupportedLanguage:
            return "Für diese Sprache ist keine Spracherkennung verfügbar."
        case .offlineUnavailable:
            return "Die deutsche Offline-Erkennung ist auf diesem Gerät nicht verfügbar."
        case .serviceUnavailable:
            return "Die Spracherkennung ist derzeit nicht verfügbar. Bitte prüfen Sie die Internetverbindung."
        case .timeout:
            return "Die Spracherkennung hat zu lange nicht geantwortet."
```

- [ ] **Step 2: 实现 Apple 分段引擎**

创建 `AsrRecognize/Services/AppleChunkEngine.swift`：

```swift
import AVFoundation
import Foundation
import Speech

final class AppleChunkEngine: ChunkTranscriptionEngine, @unchecked Sendable {
    let displayName = "System-Spracherkennung"

    private let localeIdentifier: String
    private let offlineOnly: Bool
    private var recognizer: SFSpeechRecognizer?

    init(localeIdentifier: String, offlineOnly: Bool) {
        self.localeIdentifier = localeIdentifier
        self.offlineOnly = offlineOnly
    }

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let authorized = await Self.requestAuthorization()
        guard authorized else { throw TranscriptionEngineError.permissionDenied }

        progress(0.5, "Spracherkennung wird vorbereitet…")
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw TranscriptionEngineError.unsupportedLanguage
        }
        if offlineOnly && !recognizer.supportsOnDeviceRecognition {
            throw TranscriptionEngineError.offlineUnavailable
        }
        self.recognizer = recognizer
        progress(1, "")
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let recognizer else { throw TranscriptionEngineError.notPrepared }
        guard recognizer.isAvailable || offlineOnly else {
            throw TranscriptionEngineError.serviceUnavailable
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw TranscriptionEngineError.emptyResult
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let destination = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                destination.update(from: base, count: samples.count)
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = offlineOnly
        request.addsPunctuation = true
        request.append(buffer)
        request.endAudio()

        let box = RecognitionBox()
        let text = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    let guardOnce = ContinuationGuard()
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error {
                            guard guardOnce.claim() else { return }
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let result, result.isFinal, guardOnce.claim() else { return }
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                    box.set(task)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw TranscriptionEngineError.timeout
            }
            defer {
                group.cancelAll()
                box.cancel()
            }
            guard let value = try await group.next() else {
                throw TranscriptionEngineError.emptyResult
            }
            return value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionEngineError.emptyResult }
        return trimmed
    }

    func unload() async {
        recognizer = nil
    }

    private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

private final class ContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func set(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}
```

- [ ] **Step 3: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add Apple Speech chunk engine for file transcription"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: 模拟器构建 PASS（引擎无法在模拟器识别，但必须能编译）。

---

### Task 10: 音频文件转写流水线

**Files:**
- Create: `AsrRecognize/Services/AudioFileTranscriber.swift`

- [ ] **Step 1: 实现流水线**

创建 `AsrRecognize/Services/AudioFileTranscriber.swift`：

```swift
import AVFoundation
import Combine
import Foundation

enum AudioFileTranscriberError: LocalizedError {
    case unreadable
    case noAudio

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Die Audiodatei konnte nicht gelesen werden."
        case .noAudio:
            return "Die Audiodatei enthält keine Tonspur."
        }
    }
}

@MainActor
final class AudioFileTranscriber: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, transcribing, paused, finished, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var processedTime: TimeInterval = 0
    @Published private(set) var estimatedRemaining: TimeInterval?
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var statusText = ""
    @Published private(set) var loadFraction: Double = 0
    @Published private(set) var errorMessage: String?

    private var job: ImportJob?
    private var audioURL: URL?
    private var engine: ChunkTranscriptionEngine?
    private var worker: Task<Void, Never>?
    private var pauseRequested = false
    private var cancelRequested = false
    private var startedAt: Date?
    private let store = ImportJobStore.shared
    private let converter = Audio16kConverter()

    var framesProcessed: Int64 { job?.framesProcessed ?? 0 }

    func start(job: ImportJob, audioURL: URL, engine: ChunkTranscriptionEngine, resume: Bool) {
        self.job = job
        self.audioURL = audioURL
        self.engine = engine
        pauseRequested = false
        cancelRequested = false
        errorMessage = nil
        estimatedRemaining = nil
        startedAt = nil
        totalDuration = job.duration
        worker?.cancel()
        worker = Task { [weak self] in
            await self?.run(resume: resume)
        }
    }

    func pause() {
        guard phase == .transcribing else { return }
        pauseRequested = true
        statusText = "Wird pausiert…"
    }

    func resume() {
        guard phase == .paused, let job, let audioURL, let engine else { return }
        start(job: job, audioURL: audioURL, engine: engine, resume: true)
    }

    func cancel() {
        cancelRequested = true
        worker?.cancel()
    }

    private func run(resume: Bool) async {
        guard var job, let audioURL, let engine else { return }
        phase = .preparing
        statusText = "Audio wird vorbereitet…"

        do {
            try await engine.prepare { [weak self] fraction, message in
                Task { @MainActor in
                    guard let self else { return }
                    self.loadFraction = fraction
                    if !message.isEmpty { self.statusText = message }
                }
            }

            let file = try AVAudioFile(forReading: audioURL)
            let format = file.processingFormat
            let totalFrames = file.length
            guard totalFrames > 0, format.sampleRate > 0 else { throw AudioFileTranscriberError.unreadable }

            if resume {
                let existing = await store.segments(for: job.id)
                let resumeTime = Double(job.framesProcessed) / format.sampleRate
                segments = existing.filter { $0.timestamp < resumeTime - 0.3 }
            } else {
                segments = []
                job.framesProcessed = 0
                job.sourceSampleRate = format.sampleRate
                try await store.update(job)
            }

            file.framePosition = AVAudioFramePosition(job.framesProcessed)
            var framesRead = Int64(job.framesProcessed)
            let capacity: AVAudioFrameCount = 16_384
            let vad = VoiceActivityDetector()

            job.status = .running
            try await store.update(job)
            phase = .transcribing
            statusText = ""
            startedAt = Date()

            while framesRead < totalFrames {
                if cancelRequested { throw CancellationError() }
                if pauseRequested {
                    job.framesProcessed = framesRead
                    job.status = .paused
                    try await store.update(job)
                    self.job = job
                    pauseRequested = false
                    estimatedRemaining = nil
                    phase = .paused
                    statusText = ""
                    return
                }
                if attemptMemoryThrottle(audioURL: audioURL) {
                    await Task.yield()
                }

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                    throw AudioFileTranscriberError.unreadable
                }
                try file.read(into: buffer)
                if buffer.frameLength == 0 { break }

                let samples = converter.convert(buffer)
                let timestamp = Double(framesRead) / format.sampleRate
                for segment in vad.feed(samples) {
                    try await recognize(
                        segment,
                        timestamp: timestamp,
                        engine: engine,
                        job: &job
                    )
                }

                framesRead += Int64(buffer.frameLength)
                job.framesProcessed = framesRead
                try await store.update(job)
                self.job = job
                progress = min(1, Double(framesRead) / Double(totalFrames))
                processedTime = job.duration * progress
                if let startedAt, progress > 0.02 {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    estimatedRemaining = max(0, elapsed * (1 - progress) / progress)
                }
            }

            if let tail = vad.flush() {
                try await recognize(
                    tail,
                    timestamp: Double(framesRead) / format.sampleRate,
                    engine: engine,
                    job: &job
                )
            }

            job.framesProcessed = totalFrames
            job.status = .finished
            try await store.update(job)
            self.job = job
            progress = 1
            processedTime = job.duration
            estimatedRemaining = nil
            statusText = "Transkription abgeschlossen"
            phase = .finished
        } catch is CancellationError {
            statusText = ""
        } catch {
            errorMessage = error.localizedDescription
            if var current = self.job {
                current.status = .paused
                self.job = current
                try? await store.update(current)
            }
            phase = .failed
        }
    }

    private func recognize(
        _ samples: [Float],
        timestamp: TimeInterval,
        engine: ChunkTranscriptionEngine,
        job: inout ImportJob
    ) async throws {
        do {
            let text = try await transcribeWithRetry(
                samples,
                language: RecognitionLanguage.qwenHint(for: job.languageCode),
                engine: engine
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let segment = TranscriptSegment(text: trimmed, timestamp: timestamp)
            segments.append(segment)
            try await store.append(segment, to: job.id)
        } catch TranscriptionEngineError.emptyResult {
            return
        }
    }

    private func transcribeWithRetry(
        _ samples: [Float],
        language: String,
        engine: ChunkTranscriptionEngine
    ) async throws -> String {
        var attempt = 0
        while true {
            do {
                return try await engine.transcribe(samples: samples, language: language)
            } catch TranscriptionEngineError.emptyResult {
                throw TranscriptionEngineError.emptyResult
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                if attempt > 2 { throw error }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func attemptMemoryThrottle(audioURL: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
        return size > 500_000_000
    }
}
```

- [ ] **Step 2: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add streaming audio file transcription pipeline"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: 模拟器构建 PASS。

---

### Task 11: 导入设置界面

**Files:**
- Create: `AsrRecognize/Views/ImportSetupView.swift`

- [ ] **Step 1: 实现导入设置页**

创建 `AsrRecognize/Views/ImportSetupView.swift`：

```swift
import SwiftUI

struct ImportSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let job: ImportJob
    let onStart: (ASREngine, String) -> Void

    @State private var title: String
    @State private var engine: ASREngine
    @State private var languageCode: String

    init(job: ImportJob, onStart: @escaping (ASREngine, String) -> Void) {
        self.job = job
        self.onStart = onStart
        _title = State(initialValue: job.title)
        _engine = State(initialValue: ASREngine(rawValue: job.engine) ?? .apple)
        _languageCode = State(initialValue: job.languageCode)
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    fileCard
                    titleField
                    engineSection
                    languageSection
                    hint
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if engine == .qwen, !LocalModelAssets.isBundled {
                engine = .apple
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("AUDIO")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Audio importieren")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button("Abbrechen") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    private var fileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(job.originalFileName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(AppFormat.duration(job.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .glassCard()
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "TITEL")
            TextField("Titel", text: $title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "SPRACHERKENNUNG")
            Picker("Spracherkennung", selection: $engine) {
                Text("System-Spracherkennung").tag(ASREngine.apple)
                Text("Lokales Qwen3").tag(ASREngine.qwen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!LocalModelAssets.isBundled)
            if !LocalModelAssets.isBundled {
                Text("Das lokale Modell ist in dieser App-Version nicht enthalten.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "SPRACHE")
            Picker("Sprache", selection: $languageCode) {
                Text("Deutsch").tag("de-DE")
                Text("English").tag("en-US")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var hint: some View {
        Text("Bitte lassen Sie die App während der Transkription geöffnet. Bei langen Dateien kann die lokale Erkennung deutlich länger dauern als die Aufnahme.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(3)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PillButton(title: "Transkription starten", icon: "waveform") {
                settings.engine = engine
                settings.languageCode = languageCode
                onStart(engine, languageCode)
                dismiss()
            }
            Button("Abbrechen") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
```

- [ ] **Step 2: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add audio import setup screen"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: 模拟器构建 PASS。

---

### Task 12: 导入进度页、首页导入与断点恢复

**Files:**
- Create: `AsrRecognize/Views/ImportProgressView.swift`
- Modify: `AsrRecognize/Views/HomeView.swift`

- [ ] **Step 1: 实现导入进度页**

创建 `AsrRecognize/Views/ImportProgressView.swift`：

```swift
import SwiftData
import SwiftUI
import UIKit

struct ImportProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettings

    let job: ImportJob
    let audioURL: URL
    let onComplete: (ImportJob, [TranscriptSegment]) -> Void
    let onCancel: () -> Void

    @StateObject private var transcriber = AudioFileTranscriber()
    @State private var didStart = false
    @State private var showCancelAlert = false

    private var engine: ChunkTranscriptionEngine {
        switch ASREngine(rawValue: job.engine) ?? .apple {
        case .qwen:
            return Qwen3CoreMLEngine()
        case .apple:
            return AppleChunkEngine(
                localeIdentifier: RecognitionLanguage.appleLocale(for: job.languageCode),
                offlineOnly: job.offlineOnly
            )
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                topBar
                content
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .task {
            guard !didStart else { return }
            didStart = true
            transcriber.start(job: job, audioURL: audioURL, engine: engine, resume: job.framesProcessed > 0)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { transcriber.pause() }
        }
        .onChange(of: transcriber.phase) { _, phase in
            if phase == .finished {
                onComplete(job, transcriber.segments)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            transcriber.pause()
        }
        .alert("Import abbrechen?", isPresented: $showCancelAlert) {
            Button("Abbrechen", role: .cancel) {}
            Button("Verwerfen", role: .destructive) {
                transcriber.cancel()
                onCancel()
            }
        } message: {
            Text("Die importierte Audiodatei und das bisherige Transkript werden gelöscht.")
        }
    }

    private var topBar: some View {
        HStack {
            StatusPill(
                text: statusLabel,
                color: transcriber.phase == .failed ? Theme.warning : Theme.accent,
                pulse: transcriber.phase == .transcribing
            )
            Spacer()
            Button {
                showCancelAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Abbrechen")
        }
    }

    private var statusLabel: String {
        switch transcriber.phase {
        case .idle, .preparing: return "VORBEREITUNG"
        case .transcribing: return "TRANSKRIPTION"
        case .paused: return "PAUSIERT"
        case .finished: return "FERTIG"
        case .failed: return "FEHLER"
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(job.title)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text("\(Int(transcriber.progress * 100)) % · \(AppFormat.clock(transcriber.processedTime)) von \(AppFormat.clock(job.duration))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

                ProgressView(value: transcriber.progress)
                    .tint(Theme.accent)

                if let remaining = transcriber.estimatedRemaining, remaining > 1 {
                    Text("Noch ca. \(AppFormat.clock(remaining))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if let error = transcriber.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.record)
                    .lineSpacing(3)
            } else if !transcriber.statusText.isEmpty {
                Text(transcriber.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "TRANSKRIPT")
                    Spacer()
                    Text("\(transcriber.segments.count) Abschnitte")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if transcriber.segments.isEmpty {
                                Text("Die Erkennung beginnt in Kürze…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            ForEach(transcriber.segments) { segment in
                                TranscriptRow(segment: segment)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: transcriber.segments.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

            Text("Bitte lassen Sie die App geöffnet. Beim Wechsel in den Hintergrund wird pausiert.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 18)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if transcriber.phase == .failed {
                PillButton(title: "Erneut versuchen", icon: "arrow.clockwise") {
                    transcriber.resume()
                }
                if job.engine == ASREngine.qwen.rawValue {
                    PillButton(
                        title: "System-Spracherkennung verwenden",
                        icon: "waveform",
                        kind: .secondary
                    ) {
                        retryWithApple()
                    }
                }
                Button {
                    showCancelAlert = true
                } label: {
                    Text("Verwerfen")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                HStack(spacing: 14) {
                    if transcriber.phase == .paused {
                        PillButton(title: "Fortsetzen", icon: "play.fill", fullWidth: false) {
                            transcriber.resume()
                        }
                    } else {
                        PillButton(
                            title: "Pausieren",
                            icon: "pause.fill",
                            kind: .secondary,
                            fullWidth: false
                        ) {
                            transcriber.pause()
                        }
                    }
                    Spacer()
                    Button {
                        showCancelAlert = true
                    } label: {
                        Text("Abbrechen")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    private func retryWithApple() {
        var updated = job
        updated.engine = ASREngine.apple.rawValue
        updated.framesProcessed = transcriber.framesProcessed
        transcriber.start(
            job: updated,
            audioURL: audioURL,
            engine: AppleChunkEngine(
                localeIdentifier: RecognitionLanguage.appleLocale(for: job.languageCode),
                offlineOnly: job.offlineOnly
            ),
            resume: updated.framesProcessed > 0
        )
    }
}
```

- [ ] **Step 2: 首页导入与恢复**

在 `HomeView.swift` 顶部新增：

```swift
import AVFoundation
import UniformTypeIdentifiers
```

状态：

```swift
    @State private var path = NavigationPath()
    @State private var pendingImport: PendingImport?
    @State private var resumableJobs: [ImportJob] = []
    @State private var importError: String?

    struct PendingImport: Identifiable {
        let id = UUID()
        var job: ImportJob
        var audioURL: URL
    }
```

`NavigationStack` 改为 `NavigationStack(path: $path)`；把列表里现有的：

```swift
                        NavigationLink {
                            MeetingDetailView(meeting: meeting)
                        } label: {
                            MeetingCardView(meeting: meeting)
                        }
```

改为：

```swift
                        NavigationLink(value: meeting.id) {
                            MeetingCardView(meeting: meeting)
                        }
```

并在 `.sheet(...)` 链后追加：

```swift
            .navigationDestination(for: UUID.self) { id in
                if let meeting = meetings.first(where: { $0.id == id }) {
                    MeetingDetailView(meeting: meeting)
                        .environmentObject(settings)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { importAudio(from: url) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .sheet(item: $pendingImport) { pending in
                ImportSetupView(job: pending.job) { engine, language in
                    startImport(pending, engine: engine, language: language)
                }
                .environmentObject(settings)
            }
            .fullScreenCover(item: $activeImport) { active in
                ImportProgressView(
                    job: active.job,
                    audioURL: active.audioURL,
                    onComplete: { job, segments in
                        finishImport(job: job, segments: segments)
                    },
                    onCancel: {
                        cancelImport(active)
                    }
                )
                .environmentObject(settings)
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .task { await loadResumableJobs() }
```

还需要状态：

```swift
    @State private var activeImport: PendingImport?
```

在列表上方加入恢复横幅（放在 `if !meetings.isEmpty { statsStrip }` 前）：

```swift
                        if let job = resumableJobs.first {
                            resumeBanner(job)
                        }
```

实现方法：

```swift
    private func resumeBanner(_ job: ImportJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accentBright)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unvollständige Transkription")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(job.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Fortsetzen") { resume(job) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
            Button {
                discard(job)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityLabel("Verwerfen")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
    }

    private func loadResumableJobs() async {
        resumableJobs = await ImportJobStore.shared.resumableJobs()
    }

    private func importAudio(from url: URL) {
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                guard !audioTracks.isEmpty else { throw ImportValidation.Failure.invalid }
                try ImportValidation.validate(duration: duration, fileSize: size)

                let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                try ImportValidation.validateAvailableSpace(
                    required: size,
                    available: values?.volumeAvailableCapacityForImportantUsage
                )

                let destination = AudioStorage.makeImportedFileURL(extension: url.pathExtension)
                try FileManager.default.copyItem(at: url, to: destination)

                let originalName = url.lastPathComponent
                let title = FilenameSanitizer.sanitize(
                    url.deletingPathExtension().lastPathComponent,
                    fallback: "Importierte Aufnahme"
                )
                let job = ImportJob(
                    id: UUID(),
                    audioFileName: destination.lastPathComponent,
                    originalFileName: originalName,
                    title: title,
                    engine: settings.engine.rawValue,
                    languageCode: settings.languageCode,
                    offlineOnly: settings.offlineOnly,
                    duration: duration,
                    framesProcessed: 0,
                    sourceSampleRate: 0,
                    status: .running,
                    createdAt: Date()
                )
                try await ImportJobStore.shared.create(job)
                pendingImport = PendingImport(job: job, audioURL: destination)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func startImport(_ pending: PendingImport, engine: ASREngine, language: String) {
        var job = pending.job
        job.engine = engine.rawValue
        job.languageCode = language
        job.offlineOnly = settings.offlineOnly
        beforeActive(job: job, audioURL: pending.audioURL)
    }

    private func beforeActive(job: ImportJob, audioURL: URL) {
        Task {
            try? await ImportJobStore.shared.update(job)
            pendingImport = nil
            activeImport = PendingImport(job: job, audioURL: audioURL)
        }
    }

    private func resume(_ job: ImportJob) {
        guard let url = job.audioURL else {
            importError = "Die Audiodatei fehlt. Die unvollständige Transkription wird verworfen."
            discard(job)
            return
        }
        activeImport = PendingImport(job: job, audioURL: url)
    }

    private func finishImport(job: ImportJob, segments: [TranscriptSegment]) {
        let transcript = segments.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            importError = "Es wurde kein Text erkannt."
            activeImport = nil
            return
        }
        let meeting = Meeting(
            title: job.title,
            createdAt: job.createdAt,
            duration: job.duration,
            transcript: transcript,
            segments: segments,
            audioFileName: job.audioFileName,
            source: .import,
            originalFileName: job.originalFileName
        )
        modelContext.insert(meeting)
        try? modelContext.save()
        Task {
            await ImportJobStore.shared.delete(id: job.id)
            resumableJobs = await ImportJobStore.shared.resumableJobs()
        }
        activeImport = nil
        Haptics.success()
        path.append(meeting.id)
    }

    private func cancelImport(_ active: PendingImport) {
        AudioStorage.delete(named: active.job.audioFileName)
        Task {
            await ImportJobStore.shared.delete(id: active.job.id)
            resumableJobs = await ImportJobStore.shared.resumableJobs()
        }
        activeImport = nil
    }

    private func discard(_ job: ImportJob) {
        AudioStorage.delete(named: job.audioFileName)
        Task {
            await ImportJobStore.shared.delete(id: job.id)
            resumableJobs = await ImportJobStore.shared.resumableJobs()
        }
    }
```

在 `AsrRecognize/Services/AudioStorage.swift` 末尾补充便捷属性。不要把它放进 `ImportJobStore.swift`：逻辑测试会复制 `ImportJobStore.swift` 但不复制 `AudioStorage.swift`，放错位置会导致测试包编译失败。

```swift
extension ImportJob {
    var audioURL: URL? {
        let url = AudioStorage.url(for: audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
```

- [ ] **Step 3: 导入时自动刷新恢复列表**

在 `HomeView` 的 `.task { await loadResumableJobs() }` 基础上，`ImportProgressView` 中断返回后也需要刷新；在 `.fullScreenCover(item: $activeImport)` 的 `onDismiss` 中调用：

```swift
            .fullScreenCover(item: $activeImport, onDismiss: {
                Task { await loadResumableJobs() }
            }) { active in
```

- [ ] **Step 4: 重新生成工程并验证**

```bash
python tools/generate_xcodeproj.py
git add AsrRecognize AsrRecognize.xcodeproj/project.pbxproj
git commit -m "Add import progress, resume flow, and home integration"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: 模拟器构建 PASS；Logic tests PASS。

- [ ] **Step 5: 编译修复**

CI 若报错，按日志修：常见为 `PillButton` 参数名、`NavigationPath` 与 `fullScreenCover(item:)` 的 `Identifiable` 约束、`AVURLAsset.load` 的 async 可用性。修复后重复 Step 4，直到全绿。

---

### Task 13: 文档、完整 CI 与验收

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/ios-build.yml`（确认 main 分支真机构建）
- Modify: `docs/superpowers/specs/2026-10-31-german-protokoll-app-design.md`（如实现与 spec 有偏差，回写）

- [ ] **Step 1: 更新 README**

把标题改为 `# Protokoll`，功能列表改为德语版说明，并补充：

~~~markdown
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
~~~

- [ ] **Step 2: 确认 main 上真机构建仍启用**

`.github/workflows/ios-build.yml` 中 `offline-ipa` 的 `if` 必须是：

```yaml
    if: github.event_name == 'workflow_dispatch' || github.ref == 'refs/heads/main'
```

- [ ] **Step 3: 最终 CI**

```bash
git add README.md .github/workflows/ios-build.yml
git commit -m "Document German Protokoll features and test workflow"
git push
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: Logic tests PASS + Simulator PASS。

- [ ] **Step 4: 合并回 main 并触发带模型真机构建**

> 合并与推送到 main 属于对共享仓库的可见操作，执行前向用户确认。

```bash
git checkout main
git merge --no-ff feature/german-protokoll
git push origin main
RUN=$(gh run list --workflow=ios-build.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

Expected: 三个 job 全绿，产出 `AsrRecognize-simulator-appetize` 与 `AsrRecognize-unsigned-ipa`。

- [ ] **Step 5: 真机验收清单（记录到 PR/issue）**

- [ ] 全部界面德语、日期/时长为德式、无中文残留。
- [ ] 导入 5 分钟 m4a：两种引擎均完成，时间戳连续。
- [ ] 导入接近 2 小时文件：进度/ETA 正常，前台不休眠，可暂停续转。
- [ ] 处理中强杀 App：重启出现恢复横幅，续转不重复已完成段落。
- [ ] 导入音频在详情页可播放；删除会议后文件消失。
- [ ] 自定义端点生成德语纪要（DeepSeek 或欧盟托管兼容服务）。
- [ ] 导出 TXT 与原始格式音频，可在「Dateien」打开。
- [ ] 旧数据升级：已有会议正常显示，语言设置迁移为德语。

---

## 备注：任务间依赖

- Task 2 的 Formatters 被 Task 5/6 使用。
- Task 3 的 RecognitionLanguage/MeetingSource 被 Task 9/12 使用。
- Task 7/8 是 Task 10 的依赖；Task 10 被 Task 12 使用。
- Task 4 完成前模拟器构建可能因旧字段/旧文案失败，以 Logic tests 为准；Task 4 后所有构建必须绿。
- 若 CI 在 Task 5 后因 SummaryContentView 的 `settings.aiModel` 报错，确认 Task 4 已把 `@EnvironmentObject` 加好。
