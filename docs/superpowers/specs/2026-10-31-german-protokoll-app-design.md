# Protokoll — 德语会议纪要 App 改造设计

- 日期：2026-10-31
- 工程：`C:\Users\liulian\gh-work\AsrRecognize`
- 状态：设计已确认，待编写实现计划

## 1. 背景与目标

现有「纪要 / AsrRecognize」是面向中文用户的 iOS 会议录音 App：SwiftUI + SwiftData + Apple Speech + 可选本地 Qwen3-ASR 全 CoreML + DeepSeek 纪要。现在要改造为一款专供德国用户的会议纪要 App，并补齐长音频导入与导出能力。

四项需求：

1. 整个界面适配德国人的使用习惯，全部用德语展示。
2. 新增音频文件上传转录，最长支持 2 小时。
3. 上传的音频可以使用本地 ASR 模型转录。
4. 生成的文本和对应音频支持以文件形式导出。

已确认的关键决策：

| 决策点 | 结论 |
| --- | --- |
| 识别语言 | 德语为主（默认 `de-DE`），英语可选（`en-US`） |
| App 名称 | **Protokoll**；首页大标题 **Protokolle** |
| 导入入口 | 仅系统文件选择器（`UTType.audio`） |
| 长音频处理 | 前台处理 + 防息屏；离开 App 暂停，可断点续转 |
| 文本导出 | 纯文本 `.txt` |
| 音频导出 | 保留原格式 |
| 纪要结构 | 保持四块，德语标签；不增加 Teilnehmer/Agenda 字段 |
| AI 服务 | 自定义 OpenAI 兼容端点，默认 DeepSeek |
| 文件转写架构 | 方案 A：统一分块流水线（流式读取 + VAD + 引擎适配器） |

## 2. 非目标（本次不做）

- 分享扩展（Share Extension）、从其他 App「用 Protokoll 打开」。
- 后台长时间转写（BGProcessingTask）。
- PDF / DOCX / Markdown 导出。
- 多语言界面、运行时语言切换。
- 说话人分离（diarization）。
- 长转写的多段 map-reduce 摘要。
- App Store 元数据、上架素材、账号与云同步。

## 3. 德语化与德国习惯适配

### 3.1 基础设置

- `CFBundleDisplayName` = `Protokoll`；`CFBundleDevelopmentRegion` = `de`；`CFBundleLocalizations` = `[de]`。
- 界面文案直接以德语硬编码（单语产品，不做 String Catalog 与运行时切换）；所有 Swift 文件中的中文字符串必须清零，仅允许语言选项 `English`、模型名等专有名词。
- 全部文案使用正式 **Sie** 称谓。
- 权限说明改为德语：
  - `NSMicrophoneUsageDescription`：`Protokoll benötigt Zugriff auf das Mikrofon, um Besprechungen aufzunehmen und zu transkribieren.`
  - `NSSpeechRecognitionUsageDescription`：`Protokoll wandelt Ihre Aufnahmen in Text um, um daraus ein Protokoll zu erstellen.`

### 3.2 日期、时间、数字与周

统一在 `AppFormat` 使用固定 `Locale(identifier: "de_DE")` 与 ISO 周历（周一起）：

| 用途 | 格式 / 示例 |
| --- | --- |
| 会议时间 | `dd.MM.yyyy, HH:mm` → `31.10.2026, 14:30` |
| 首页日期 | `EEEE, d. MMMM` → `Samstag, 31. Oktober` |
| 仅日期 | `dd.MM.yyyy` |
| 时长 | `1 Std. 5 Min.`、`45 Sek.`、`2 Std.` |
| 字数 | `1.234 Zeichen`（`NumberFormatter`，de_DE） |
| 周统计 | ISO 周，`KW 44` |
| 默认标题 | `Protokoll vom 31.10.2026` |

识别语言映射：`de-DE → "german"`、`en-US → "english"`（Qwen3 语言提示为自由文本前缀 `language german`，已核对 speech-swift 源码）。旧版本保存的 `zh-CN` 在 `AppSettings.init` 中自动迁移为 `de-DE`。

### 3.3 术语表

| 中文 | 德语 |
| --- | --- |
| 会议 / 会议记录 | Besprechung / Protokolle |
| 录音 | Aufnahme |
| 转写 | Transkript |
| 实时转写 | Live-Transkript |
| 纪要 | Protokoll / Zusammenfassung |
| 关键要点 | Kernpunkte |
| 待办事项 | Aufgaben |
| 负责人 | Verantwortlich |
| 截止时间 | Frist |
| 决议 | Beschlüsse |
| 设置 | Einstellungen |
| 导出 | Exportieren |
| 删除 | Löschen |
| 取消 | Abbrechen |
| 保存 | Speichern |

### 3.4 主要界面文案

**首页**
- 标题：`Protokolle`；副标题：`Samstag, 31. Oktober · 12 Besprechungen`
- 搜索占位：`Protokolle und Transkripte durchsuchen…`
- 统计：`Besprechungen diese Woche` / `Dauer diese Woche` / `Gesamt`
- 列表：`Letzte Besprechungen` / `Suchergebnisse`
- 空状态：`Noch keine Protokolle` / `Tippen Sie unten auf „Aufnahme starten“, um Ihre erste Besprechung aufzunehmen.`
- 主按钮：`Aufnahme starten`；导入按钮：`Audiodatei importieren`
- 说明：`Audio bleibt auf dem Gerät · Live-Transkript (Deutsch)`
- 删除确认：`Besprechung löschen?` / `Löschen` / `Abbrechen`

**录音页**
- 状态：`REC` / `PAUSIERT` / `BEREIT`
- `Live-Transkript`、`Noch keine Sprache erkannt…`
- 按钮：`Pausieren`、`Fortsetzen`、`Speichern & schließen`、`Verwerfen`
- 结束确认：`Aufnahme beenden?` / `Speichern & schließen` / `Verwerfen`
- 错误：`Aufnahme konnte nicht gestartet werden` 等，逐条德语化。

**导入**
- 设置页标题：`Audio importieren`；字段：`Titel`、`Dauer`、`Spracherkennung`、`Sprache`
- 引擎选项：`Lokales Qwen3`、`System-Spracherkennung`
- 按钮：`Transkription starten`、`Abbrechen`
- 处理页：`Transkription läuft…`、`%d %% · %@ von %@`、`Noch ca. %@`、`Pausieren`、`Fortsetzen`、`Abbrechen`
- 提示：`Bitte lassen Sie die App geöffnet. Bei langen Dateien kann die lokale Transkription deutlich länger dauern als die Aufnahme.`
- 完成：`Transkription abgeschlossen` → 进入详情页
- 恢复提示：`Unvollständige Transkription: %@` / `Fortsetzen` / `Verwerfen`

**详情页**
- Tab：`Zusammenfassung` / `Transkript`
- 按钮/菜单：`Kopieren`、`Exportieren`、`Neu zusammenfassen`、`Besprechung löschen`
- 元信息：`%@ · %@ · %d Zeichen`
- 导出：`Als Text (.txt)`、`Audio exportieren`
- Toast：`In die Zwischenablage kopiert`

**设置**
- 区块：`KI-ANBIETER`、`KI-PROTOKOLL`、`SPRACHERKENNUNG`、`DATENSCHUTZ`、`ÜBER`
- 字段：`Basis-URL`、`Modell`、`API-Schlüssel`、`Speichern`
- 开关：`Automatisch zusammenfassen`、`Nur auf dem Gerät`
- 引擎：`Lokales Qwen3` / `System-Spracherkennung`
- 语言：`Deutsch` / `English`
- 关于：`Version %@`

### 3.5 隐私表述（DSGVO 语境）

只陈述事实，不写「DSGVO-konform」等合规承诺：

> Audio und Transkripte bleiben auf dem Gerät. Nur bei aktivierter KI-Zusammenfassung wird der Transkripttext an den von Ihnen eingestellten Anbieter gesendet. Der API-Schlüssel wird im Schlüsselbund gespeichert.

### 3.6 排版

德语单词更长。逐个检查按钮、统计栏、设置行与状态胶囊；必要时使用 `minimumScaleFactor`、`lineLimit(2)` 或纵向布局，避免截断。动态字体暂不支持（保持现有固定字号体系）。

## 4. 音频导入与长音频转写

### 4.1 用户体验流程

1. 首页点击导入按钮 → `fileImporter(allowedContentTypes: [.audio])`。
2. 校验：`AVURLAsset.load(.duration)` ≤ 7200 秒；复制后文件 ≤ 1.5 GB；必须含音轨。失败时显示德语错误并返回。
3. 复制到 `Documents/Recordings/<UUID>.<原扩展名>`（安全作用域 URL 不可长期持有）。
4. 弹出导入设置：标题默认取原文件名（去扩展名与首尾空白，空则 `Importierte Aufnahme`），显示时长，选择引擎与语言。
5. 转写页：进度、已处理/总时长、预计剩余、实时文本、暂停/继续/取消。处理期间 `isIdleTimerDisabled = true`。
6. 完成：写入 `Meeting`，进入详情页；若开启自动纪要且已配置 Key，由详情页现有逻辑自动生成；删除检查点。
7. 取消：二次确认，删除音频副本与检查点。

App 进入后台时自动暂停；回前台显示「Fortsetzen」。App 被系统杀死后，下次启动首页出现恢复横幅。

### 4.2 支持格式

`m4a, mp3, wav, caf, aac, aiff, flac`（AVFoundation 可解码格式）。不支持的格式给出 `Dieses Audioformat wird nicht unterstützt.`。

### 4.3 流水线

新增 `AudioFileTranscriber`（`@MainActor ObservableObject`），后台 `Task` 执行：

```
AVAudioFile(forReading:)
  └─ 每次读取 16_384 帧（processingFormat）
     └─ Audio16kConverter → 16 kHz / mono / Float32
        └─ VoiceActivityDetector.feed → ≤15 秒语音段
           └─ ChunkTranscriptionEngine.transcribe(samples:language:)（串行）
              └─ TranscriptSegment(timestamp: framesRead / sampleRate)
```

- 结束前 `vad.flush()` 处理最后一段。
- 内存恒定：不加载整段音频；2 小时文件仅保留当前缓冲与文本。
- 进度 = 已读源帧 / `file.length`；预计剩余 = 已用时间 ×（1 − 进度）/ 进度，每秒刷新。
- 暂停：当前段识别完成后停止循环并保存检查点。
- 断点续转：`file.framePosition = framesProcessed` 继续；VAD 状态不持久化，续转后的第一段可能从句中开始，时间戳保持连续（可接受）。

### 4.4 引擎适配器

沿用现有 `ChunkTranscriptionEngine` 协议与 `TranscriptionEngineError`：

- **Qwen3CoreMLEngine（复用）**：`prepare()` 带加载进度；`language: "german" | "english"`。
- **AppleChunkEngine（新增）**：
  - `SFSpeechRecognizer(locale: de-DE/en-US)`；`offlineOnly` 时 `requiresOnDeviceRecognition = true`，不支持则报错。
  - 每段创建 `SFSpeechAudioBufferRecognitionRequest`，把 16 kHz Float32 数据装入 `AVAudioPCMBuffer` 追加后 `endAudio()`，等待 final result；超时 60 秒、最多重试 2 次。
  - 空结果视为无语音，跳过该段。
  - `prepare()` 请求语音识别授权与本地语言可用性检查。

### 4.5 检查点

目录：`Application Support/ImportJobs/<jobID>/`

- `state.json`（原子写入）：
  ```json
  {
    "id": "UUID",
    "audioFileName": "UUID.m4a",
    "originalFileName": "Besprechung.m4a",
    "title": "Besprechung",
    "engine": "qwen",
    "languageCode": "de-DE",
    "offlineOnly": true,
    "duration": 7200.0,
    "framesProcessed": 1234567,
    "sourceSampleRate": 44100,
    "status": "running",
    "createdAt": "2026-10-31T10:00:00Z"
  }
  ```
- `segments.jsonl`：每行一个 `TranscriptSegment` JSON，识别完一段立即追加。
- 完成后删除整个 job 目录；启动时扫描 `status != finished` 的作业，音频缺失则提示放弃。

### 4.6 数据模型变更

`Meeting` 新增：

- `var sourceRaw: String = "recording"`（`recording` / `import`；带默认值，SwiftData 轻量迁移）
- `var originalFileName: String?`

初始化方法补充默认参数。`AudioStorage` 新增 `makeImportedFileURL(extension:)`，导入音频与录音同目录存储，删除会议时一并删除。

### 4.7 错误处理（德语）

| 场景 | 文案 / 行为 |
| --- | --- |
| 超过 2 小时 | `Die Audiodatei ist länger als 2 Stunden.` |
| 超过 1.5 GB | `Die Audiodatei ist zu groß (maximal 1,5 GB).` |
| 无法解码 / 无音轨 | `Die Audiodatei konnte nicht gelesen werden.` |
| 模型缺失 | `Das lokale Modell ist in dieser App-Version nicht enthalten.` + 按钮 `System-Spracherkennung verwenden` |
| 模拟器无 ANE | `Das lokale Modell benötigt ein echtes Gerät.` + 同上 |
| 无语音权限 | `Spracherkennung ist nicht erlaubt. Bitte in den iOS-Einstellungen aktivieren.` |
| 转写中断 | 暂停并保留检查点，提供 `Erneut versuchen` / `System-Spracherkennung verwenden` / `Verwerfen` |
| 磁盘空间不足 | `Nicht genügend Speicherplatz für die Audiodatei.` |

## 5. AI 纪要：可配置 OpenAI 兼容端点

### 5.1 设置项

`AppSettings` 新增并持久化：

- `aiBaseURL`（UserDefaults，默认 `https://api.deepseek.com`）
- `aiModel`（UserDefaults，默认 `deepseek-chat`）
- API Key：Keychain，按端点分账号保存（`account = 规范化后的 Base-URL`），切换端点无需重填；旧字段迁移到默认端点。

规则：

- Base-URL 只接受 `https://`，去掉结尾 `/`；请求地址为 `{base}/chat/completions`。
- 界面提示可填 `https://api.openai.com/v1`、Mistral 等兼容地址。
- 请求头 `Authorization: Bearer <key>`，超时 180 秒。

### 5.2 服务与提示词

`DeepSeekService` 重命名为 `AISummaryService`：

- 输入：转写文本（上限 120,000 字符，超出截断并在 UI 显示 `Transkript für die Zusammenfassung gekürzt.`）。
- 德语系统提示词：角色「erfahrener Protokollassistent」，只输出 JSON，全部德语，禁止编造，任务最多 8 条，缺失类别返回空数组，`overview` 100–200 词。
- 输出 JSON 键保持不变：`overview`、`keyPoints`、`actionItems[{task,owner,deadline}]`、`decisions`，确保 `MeetingSummary` 解码兼容。
- 错误全部德语：未配置 Key、URL 无效、HTTP 错误（含服务端 message）、超时、返回无法解析。

### 5.3 界面

- 详情页四个区块：`Zusammenfassung`、`Kernpunkte`、`Aufgaben`（`Verantwortlich · %@`、`Frist · %@`）、`Beschlüsse`。
- 状态胶囊显示当前模型名（大写），替代固定 `DEEPSEEK`。
- 未配置时展示 `KI-Zusammenfassung einrichten` 卡片，跳转设置。

## 6. 导出

新增 `ExportService`：

### 6.1 文本

- 内容顺序：标题、`Datum`、`Dauer`、`Zusammenfassung`、`Kernpunkte`、`Aufgaben`、`Beschlüsse`、`Transkript`；无纪要时省略纪要区块，只输出标题/元信息/转写。
- 编码 UTF-8；文件名 `Protokoll_<清洗后标题>_<yyyy-MM-dd>.txt`，写入临时目录后通过分享面板导出（存入「Dateien」、邮件、AirDrop 等）。

### 6.2 音频

- 保留原始容器与编码；扩展名沿用存储文件（录音 `.caf`，导入文件为原扩展名）。
- 导出名 `<清洗后标题>.<ext>`；先尝试 `FileManager.linkItem`（同卷硬链接，无拷贝），失败再复制。
- 大文件提示 `Bei großen Dateien kann der Export einige Sekunden dauern.`
- 每次导出前清理上次生成的临时文件。

### 6.3 文件名清洗

- 替换 `/ \ : * ? " < > |` 与控制字符为 `-`；合并连续空白；去首尾空格与点号；UTF-8 长度 ≤ 60；空则用 `Protokoll`。保留德语变音字母（ä ö ü ß）。

### 6.4 入口

详情页 `…` 菜单 → `Exportieren` 子菜单（TXT、音频），使用 `ShareLink` 分享文件 URL。首页不做导出。

## 7. 测试与构建

本机无 Swift/Xcode，无法本地编译；以 GitHub Actions 为唯一验证通道。

### 7.1 单元测试

`tools/run-logic-tests.sh` 在 CI 的 macOS runner 上把纯逻辑源码（`Formatters.swift`、`MeetingSummary.swift`、`TranscriptSegment.swift`、`RecognitionLanguage.swift`、`ExportService.swift`、`ImportJobStore.swift`、`ImportValidation.swift`、`AISummaryRequest.swift`）复制进临时 Swift Package，与 `ProtokollTests/*.swift` 一起执行 `swift test`。这些文件只依赖 Foundation，不引入 SwiftData/UIKit，避免维护第二套 XCTest target。

覆盖：

- `AppFormat`：德语日期、时长、字数、ISO 周、默认标题。
- `ExportService`：TXT 内容（含/不含纪要）、文件名清洗（变音字母、非法字符、长度）。
- `ImportJobStore`：`state.json` + `segments.jsonl` 读写与恢复。
- 导入校验：时长/大小边界（7200 秒、1.5 GB）。
- AI 请求：https 校验、端点拼接、德语提示词、12 万字符截断、JSON 解析。

CI 新增独立 `logic-tests` job，不依赖模拟器。

### 7.2 构建

- 保持现有两个 job（模拟器包、带模型未签名 IPA）与 Xcode 26 选择逻辑。
- 新增测试 job/步骤后，push 触发全量验证；失败按日志迭代。

### 7.3 真机验收清单

1. 所有界面德语、日期/时长为德式、无中文残留。
2. 导入 5 分钟 m4a：两种引擎均能完成，时间戳连续。
3. 导入接近 2 小时文件：进度/ETA 正常、App 保持前台不休眠、可暂停续转。
4. 处理中强杀 App：重启出现恢复横幅，续转不重复已完成段落。
5. 导入音频在详情页可播放；删除会议后文件消失。
6. 自定义端点（DeepSeek 或欧盟托管 OpenAI 兼容服务）生成德语纪要。
7. 导出 TXT 与原始格式音频，可在「Dateien」打开。
8. 旧数据升级：已有会议的标题/转写/纪要正常显示，语言设置迁移为德语。

## 8. 文件变更清单

**新增**

- `AsrRecognize/Models/MeetingSource.swift`
- `AsrRecognize/Services/AudioFileTranscriber.swift`
- `AsrRecognize/Services/AppleChunkEngine.swift`
- `AsrRecognize/Services/ImportJobStore.swift`
- `AsrRecognize/Services/ImportValidation.swift`
- `AsrRecognize/Services/ExportService.swift`
- `AsrRecognize/Services/AISummaryService.swift`（由 `DeepSeekService.swift` 重命名改造）
- `AsrRecognize/Views/ImportSetupView.swift`
- `AsrRecognize/Views/ImportProgressView.swift`
- `ProtokollTests/…`（逻辑测试源码）+ `tools/run-logic-tests.sh`

**修改**

- `AppSettings.swift`、`Meeting.swift`、`AudioStorage.swift`、`Formatters.swift`
- `LiveTranscriber.swift`、`LocalTranscriber.swift`、`Qwen3CoreMLEngine.swift`（德语错误/语言映射）
- `HomeView.swift`、`RecordingView.swift`、`MeetingDetailView.swift`、`SummaryContentView.swift`、`SettingsView.swift`、`Design/Components.swift`
- `Info.plist`、`tools/generate_xcodeproj.py`、`.github/workflows/ios-build.yml`、`README.md`

## 9. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 本地 Qwen3 德语准确率未在真机验证 | 保留系统语音兜底；验收清单对比两种引擎 |
| 2 小时本地转写耗时长、发热 | 明确提示、防息屏、可暂停续转；不承诺后台 |
| iOS 对 mp3/flac 解码差异 | 启动前用 `AVAudioFile` 试打开，失败即报格式错误 |
| SwiftData 新增字段迁移失败 | 新字段给默认值/可选，验收旧数据升级 |
| ShareLink 导出大文件耗时 | 硬链接优先；提示等待；只导出原始文件不转码 |
| 自定义端点兼容性不一 | 严格 OpenAI Chat Completions 结构；错误信息原样展示服务端 message |
| 无本地编译环境 | CI 全量构建 + 单测；小步提交降低回滚成本 |
| speech-swift API 变动 | 继续使用 `transcribeWithoutMLX`；语言提示为自由文本，已核对源码 |

## 10. 验收标准

- 需求 1：界面、权限弹窗、导出内容全德语；日期/时长/周德式；App 名 Protokoll；无中文残留。
- 需求 2：可从「Dateien」导入 ≤2 小时音频并完成转写。
- 需求 3：导入音频可选本地 Qwen3 模型完成转写，模型不可用时自动提示切换系统语音。
- 需求 4：详情页可导出 `.txt`（含纪要+转写）与原始格式音频文件。
- CI：模拟器与真机构建通过，单元测试通过。
