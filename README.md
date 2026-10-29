# 纪要 · AsrRecognize

一款极简科技风的 iOS 会议纪要 App：实时语音转写、本地保存、可选 AI 纪要。

- SwiftUI + SwiftData + Apple Speech + DeepSeek
- 可选本地 Qwen3-ASR（全 Core ML，离线），基于 speech-swift
- iOS 18+
- 深色界面、实时声波、玻璃质感卡片、触觉反馈

> ⚠️ 本工程在 Windows 上生成。iOS App 必须在 macOS + Xcode 中编译运行，Windows 无法直接运行。

---

## 一、运行（约 1 分钟）

1. 把整个 `AsrRecognize` 文件夹复制到 Mac。
2. 双击 `AsrRecognize.xcodeproj`，或用 Xcode 打开它。
3. 顶部 Scheme 选择 **AsrRecognize**，运行目标选择 **iPhone 模拟器**（如 iPhone 16）或已连接的真机。
4. 按 **⌘R** 运行。

**模拟器**：无需签名，开箱即用。
**真机**：选中项目 Target → `Signing & Capabilities` → 勾选 `Automatically manage signing` → 选择你的 Apple ID Team。若提示 Bundle Identifier 被占用，把 `com.liulian.AsrRecognize` 改成 `com.你的名字.AsrRecognize`。

### 环境要求

| 项目 | 要求 |
| --- | --- |
| macOS | 14.5 或更新（Xcode 16 的要求） |
| Xcode | 15 或更新（推荐 16） |
| 运行系统 | iOS 18.0+（模拟器或真机；本地 Qwen3 引擎需要真机） |
| 网络 | 语音识别与 AI 纪要需要网络（可切换为设备端识别） |

> 语音识别在模拟器上可能不稳定或不支持，完整体验建议使用真机。

---

## 二、首次使用

1. 打开 App，点底部 **开始记录**。
2. 允许 **麦克风** 与 **语音识别** 权限。
3. 说话时文字会实时出现在界面中；结束后点 **完成** 保存。
4. 会议详情页可：
   - 播放原始录音
   - 编辑标题
   - 查看转写原文 / 生成 AI 纪要
   - 分享 Markdown 纪要

### 配置 DeepSeek（可选，用于 AI 纪要）

1. 首页右上角进入 **设置**。
2. 点“获取”打开 platform.deepseek.com 创建 API Key。
3. 粘贴到输入框并点 **保存 API Key**（存放在系统钥匙串）。
4. 回到任意会议详情页，点 **生成纪要**；也可以在设置中保持“自动生成纪要”开启。

> 只有转写文本会发送到 DeepSeek，音频始终留在本机。

---

## 三、功能说明

- **实时转写**：Apple Speech 中文/英文识别，每 50 秒自动续接识别任务，长会议不会中断。
- **录音留存**：以 CAF 格式保存在 App 沙盒 `Documents/Recordings`，可在详情页回放。
- **本地存储**：会议、转写、纪要使用 SwiftData 持久化；删除会议会同时删除录音。
- **AI 纪要**：DeepSeek 输出结构化 JSON：摘要、关键要点、待办事项（负责人/截止时间）、会议决议。
- **搜索**：首页可按标题或转写正文搜索。
- **隐私**：API Key 存 Keychain；无账号、无云端同步、无统计 SDK。

### 识别引擎 / 识别语言

设置中可切换两种引擎：

- **系统语音**：Apple Speech，实时出字，可用“仅设备端识别”减少联网。
- **本地 Qwen3**：Qwen3-ASR 0.6B 全 Core ML 推理，完全离线；按语音段出字（非逐字），
  模型约 0.9GB 随 App 打包，首次加载约 1 分钟，需要 iOS 18 与真机（模拟器无 ANE）。
  模型缺失时录音页会提示并提供“改用系统语音识别”。

识别语言可在中文与 English 之间切换，切换后对下一次录音生效。

---

## 四、目录结构

```
AsrRecognize/
├── AsrRecognize.xcodeproj        # 工程文件（含共享 Scheme）
├── AsrRecognize/
│   ├── App/                      # App 入口、SwiftData 容器
│   ├── Views/
│   │   ├── HomeView.swift        # 会议列表、搜索、统计
│   │   ├── RecordingView.swift   # 录音与实时转写
│   │   ├── MeetingDetailView.swift
│   │   ├── SummaryContentView.swift
│   │   └── SettingsView.swift
│   ├── Services/
│   │   ├── LiveTranscriber.swift # AVAudioEngine + Speech 实时转写
│   │   ├── Qwen3/                # 本地 Qwen3-ASR：引擎、VAD、重采样、会话
│   │   ├── AudioPlayer.swift
│   │   ├── AudioStorage.swift
│   │   ├── DeepSeekService.swift
│   │   ├── KeychainStore.swift
│   │   └── AppSettings.swift
│   ├── Models/                   # Meeting / MeetingSummary / TranscriptSegment
│   ├── Design/                   # 主题色、组件、波形
│   ├── Utilities/                # 格式化、触觉反馈
│   ├── Assets.xcassets           # AppIcon / AccentColor
│   └── Info.plist                # 权限、后台音频、启动屏
├── tools/
│   ├── generate_xcodeproj.py     # 重新生成 .xcodeproj
│   ├── prepare-model.sh          # 下载并编译 Qwen3 CoreML 模型
│   └── make_icon.py              # 生成 1024 AppIcon
└── README.md
```

工程文件由脚本生成，源文件按目录加入编译。正常使用不需要运行脚本。

---

## 五、常见问题

**Q：编译报 Signing 错误？**
真机运行需要在 `Signing & Capabilities` 选择 Team；模拟器不需要。

**Q：一直显示“正在准备麦克风”？**
检查系统设置中是否允许了麦克风与语音识别；模拟器请确认 Mac 麦克风可用。

**Q：识别不到文字 / 频繁中断？**
Apple Speech 依赖网络与系统服务。确认网络可用；真机效果更好；可在设置里关闭“仅设备端识别”后重试。

**Q：AI 纪要报错？**
常见原因：Key 错误（401）、余额不足（402）、请求过频（429）、网络超时。检查设置后重试。
单次最多分析约 2 万字，超出部分会被截断，界面会提示。

**Q：数据存在哪里？**
录音在 App 沙盒 `Documents/Recordings`，会议数据在 SwiftData 数据库，API Key 在 Keychain。卸载 App 会全部清除。

**Q：本地 Qwen3 引擎提示“模型未打包”？**
仓库不包含 0.9GB 模型。在 Mac 上执行 `bash tools/prepare-model.sh` 后重新编译，
或用 GitHub Actions 的带模型构建（见第七节）。

**Q：支持 iPad / 横屏吗？**
当前仅 iPhone 竖屏，部署目标 iOS 18。

---

## 六、重新生成工程（可选）

```bash
cd AsrRecognize
python3 tools/generate_xcodeproj.py   # 重写 project.pbxproj 与共享 Scheme
python3 tools/make_icon.py            # 重新生成 AppIcon（需要 Pillow、numpy）
```

如 Xcode 打开工程异常，可先运行生成脚本再重新打开。

---

## 七、零 Mac 方案：GitHub Actions 云构建

仓库已包含 `.github/workflows/ios-build.yml`，不需要 Mac，也不需要签名证书。一次构建产出两个作业：

| Job / Artifact | 内容 | 用途 |
| --- | --- | --- |
| `simulator-app` → `AsrRecognize-simulator-appetize` | 不含模型，Debug 模拟器包，约几十 MB | 上传 Appetize.io，在 Windows 浏览器里操作界面 |
| `offline-ipa` → `AsrRecognize-unsigned-ipa` | 先下载并编译 Qwen3 模型（约 0.9GB），Release 真机包 | 用 Sideloadly 签名装到 iPhone，可离线转写 |

- 模拟器无 ANE，本地 Qwen3 引擎跑不动，所以模拟器包**不带模型**，默认走系统语音。
- 带模型的 `offline-ipa` 作业较慢：下载 + coremlcompiler 编译约 20–40 分钟，产物约 0.9GB。
- 只需要验证编译时，可在 Run workflow 时把 `include_model` 关掉。

### 1. 把项目推送到 GitHub

先在 GitHub 新建一个空仓库（public 或 private），然后在本目录执行：

```bash
cd C:\AsrRecognize
git init
git add .
git commit -m "AsrRecognize iOS app"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 2. 运行云端构建

打开仓库页面 → **Actions** → 左侧 **Build AsrRecognize** → **Run workflow** → 选择 `main` 并运行。
模拟器作业约 3–6 分钟；带模型作业通常 20–40 分钟（取决于 Hugging Face 下载速度）。完成后在本次运行页面底部的 **Artifacts** 下载：

- `AsrRecognize-simulator-appetize.zip`：解压一次，得到内层 `AsrRecognize-simulator.zip`（里面是 `.app`）
- `AsrRecognize-unsigned-ipa.zip`：解压一次，得到 `AsrRecognize-unsigned.ipa`

> GitHub 下载的 Artifact 本身是外层 zip，不要直接把它上传给 Appetize。

> 公开仓库的 Actions 通常免费；私有仓库会消耗 macOS 构建分钟，且 macOS 按 10 倍计费。

### 3. 浏览器打开（Appetize.io，无需安装到本地）

1. 注册并登录 [Appetize.io](https://appetize.io)。
2. 点击 **New App** → 平台选 **iOS** → 上传解压后的 `AsrRecognize-simulator.zip`。
3. 上传完成后打开详情页的链接，即可在浏览器里点按 App。

注意：免费额度约 30 分钟/月、单次会话 3 分钟；Appetize 主要用来预览界面和交互，**麦克风、Apple Speech 与本地模型推理都不可用**，实时转写请以真机为准。

### 4. 安装到 iPhone（Windows + Sideloadly）

1. 在 Windows 安装 [Sideloadly](https://sideloadly.io)。
2. iPhone 用 USB 连接电脑，把 `AsrRecognize-unsigned.ipa` 拖入 Sideloadly。
3. 输入你的 Apple ID（免费账号即可），点 **Start** 签名并安装。
4. iPhone 首次安装后需开启开发者模式：**设置 → 隐私与安全性 → 开发者模式**，打开并重启。
5. 若提示“未受信任的开发者”：**设置 → 通用 → VPN 与设备管理** → 信任你的 Apple ID。

免费 Apple ID 签名的 App **7 天后过期**，到期用同样步骤重新签名即可。安装后在设置里把引擎切到“本地 Qwen3”，即可离线转写（首次加载约 1 分钟）。
