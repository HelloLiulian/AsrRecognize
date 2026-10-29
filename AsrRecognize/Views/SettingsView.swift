import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var draftKey = ""
    @State private var keyVisible = false
    @State private var savedFlash = false
    @State private var didLoad = false

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    apiSection
                    summarySection
                    recognitionSection
                    aboutSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            savedToast
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftKey = settings.apiKey
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Theme.textTertiary)

                Text("设置")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("完成设置")
        }
    }

    // MARK: - API

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "DEEPSEEK")

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accentBright)
                        Text("API Key")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Spacer()

                    if let url = URL(string: "https://platform.deepseek.com/api_keys") {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Text("获取")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accentBright)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Group {
                        if keyVisible {
                            TextField("sk-…", text: $draftKey)
                        } else {
                            SecureField("sk-…", text: $draftKey)
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        Haptics.tap()
                        keyVisible.toggle()
                    } label: {
                        Image(systemName: keyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(keyVisible ? "隐藏 API Key" : "显示 API Key")
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )

                PillButton(title: "保存 API Key", icon: "checkmark") {
                    saveKey()
                }

                Text("密钥仅保存在本机钥匙串。生成纪要时，转写文本会发送到 DeepSeek。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)
            }
            .glassCard()
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "AI 纪要")

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动生成纪要")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("录音结束后自动调用 DeepSeek")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("自动生成纪要", isOn: $settings.autoSummarize)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
                .padding(.vertical, 14)

                Divider()
                    .overlay(Theme.stroke)

                HStack {
                    Text("模型")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(settings.model)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.accentBright)
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
    }

    // MARK: - Recognition

    private var recognitionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "语音识别")

            VStack(alignment: .leading, spacing: 14) {
                Picker("识别引擎", selection: $settings.engine) {
                    Text("系统语音").tag(ASREngine.apple)
                    Text("本地 Qwen3").tag(ASREngine.qwen)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(engineDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)

                Divider()
                    .overlay(Theme.stroke)

                Text("识别语言")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Picker("识别语言", selection: $settings.languageCode) {
                    Text("中文").tag("zh-CN")
                    Text("English").tag("en-US")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()
                    .overlay(Theme.stroke)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("仅设备端识别")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("音频不离开设备，准确率可能略低")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("仅设备端识别", isOn: $settings.offlineOnly)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
            }
            .glassCard()
        }
    }

    private var engineDescription: String {
        if settings.engine == .qwen {
            guard LocalModelAssets.isBundled else {
                return "当前安装包未包含本地模型，录音时会提示并建议改用系统语音。"
            }
            return "完全离线，音频不出设备。模型约 0.9GB，首次加载约 1 分钟，仅支持 iOS 18 与真机。"
        }
        return "使用 Apple Speech，可按「仅设备端识别」开关切换离线与否。"
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "关于")

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("版本")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(versionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Divider()
                    .overlay(Theme.stroke)

                Text("语音由 Apple Speech 实时转写，会议纪要由 DeepSeek 生成。音频与文字默认仅存储在本机。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.success)
                    Text("本地优先 · 隐私可控")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var savedToast: some View {
        if savedFlash {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                Text("已保存")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.elevated))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func saveKey() {
        settings.apiKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            savedFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                savedFlash = false
            }
        }
    }
}
