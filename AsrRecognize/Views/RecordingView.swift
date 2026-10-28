import SwiftData
import SwiftUI
import UIKit

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings

    @StateObject private var transcriber = LiveTranscriber()

    @State private var didStart = false
    @State private var showExitAlert = false
    @State private var showEmptyAlert = false

    private var hasAnyContent: Bool {
        !transcriber.segments.isEmpty
            || !transcriber.partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                topBar

                if transcriber.isRecording || transcriber.isPaused {
                    recordingContent
                } else if let message = transcriber.errorMessage {
                    errorState(message)
                } else {
                    preparingState
                }
            }
            .alert("没有识别到内容", isPresented: $showEmptyAlert) {
                Button("继续记录", role: .cancel) {}
                Button("放弃本次", role: .destructive) {
                    transcriber.discard()
                    dismiss()
                }
            } message: {
                Text("麦克风没有捕捉到可用的语音，请靠近麦克风再试。")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .task {
            guard !didStart else { return }
            didStart = true
            await transcriber.start(language: settings.languageCode, offlineOnly: settings.offlineOnly)
        }
        .onDisappear {
            if transcriber.isRecording {
                transcriber.stop()
            }
        }
        .alert("结束本次记录？", isPresented: $showExitAlert) {
            if hasAnyContent {
                Button("保存并退出") { finish() }
            }
            Button("放弃并退出", role: .destructive) {
                transcriber.discard()
                dismiss()
            }
            Button("继续记录", role: .cancel) {}
        } message: {
            Text("保存后会出现在会议列表中。")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                if transcriber.isRecording || hasAnyContent {
                    showExitAlert = true
                } else {
                    transcriber.discard()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭")

            Spacer()

            StatusPill(
                text: recorderStatusText,
                color: recorderStatusColor,
                pulse: transcriber.isRecording && !transcriber.isPaused
            )

            Spacer()

            Button {
                finish()
            } label: {
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(!transcriber.isRecording && transcriber.segments.isEmpty)
            .opacity(transcriber.isRecording || !transcriber.segments.isEmpty ? 1 : 0.35)
            .accessibilityLabel("结束并保存")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var recorderStatusText: String {
        if transcriber.isRecording {
            return transcriber.isPaused ? "PAUSED" : "REC"
        }
        return "STANDBY"
    }

    private var recorderStatusColor: Color {
        if transcriber.isRecording {
            return transcriber.isPaused ? Theme.warning : Theme.record
        }
        return Theme.textTertiary
    }

    // MARK: - Recording content

    private var recordingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            VStack(spacing: 16) {
                Text(AppFormat.clock(transcriber.elapsed))
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                LiveWaveform(
                    level: transcriber.level,
                    isActive: transcriber.isRecording && !transcriber.isPaused
                )
                .frame(height: 72)
                .padding(.horizontal, 28)

                StatusPill(text: recognitionLabel, color: Theme.accent)
            }

            transcriptPanel
                .padding(.horizontal, 18)
                .padding(.top, 24)

            Spacer(minLength: 14)

            controls
                .padding(.bottom, 20)
        }
    }

    private var recognitionLabel: String {
        if settings.languageCode == "en-US" {
            return settings.offlineOnly ? "ENGLISH · OFFLINE" : "ENGLISH · LIVE"
        }
        return settings.offlineOnly ? "中文 · 离线识别" : "中文 · 实时转写"
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "实时转写")
                Spacer()
                Text("\(transcriber.segments.count) 段")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if transcriber.segments.isEmpty && transcriber.partialText.isEmpty {
                            Text("开始说话，文字会实时出现在这里…")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                        }

                        ForEach(transcriber.segments) { segment in
                            TranscriptRow(segment: segment)
                        }

                        if !transcriber.partialText.isEmpty {
                            TranscriptRow(
                                segment: TranscriptSegment(
                                    text: transcriber.partialText,
                                    timestamp: transcriber.elapsed
                                ),
                                isPartial: true
                            )
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: transcriber.segments.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: transcriber.partialText) { _, _ in
                    scrollToBottom(proxy)
                }
            }
            .frame(minHeight: 160, maxHeight: 260)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 30) {
            Button {
                Haptics.tap()
                if transcriber.isPaused {
                    transcriber.resume()
                } else {
                    transcriber.pause()
                }
            } label: {
                Image(systemName: transcriber.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(transcriber.isPaused ? "继续录音" : "暂停录音")

            Button {
                finish()
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Theme.recordDeep, Theme.record],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 78, height: 78)
                        .shadow(color: Theme.record.opacity(0.4), radius: 22, y: 6)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("结束并保存")
        }
    }

    // MARK: - Preparing / error

    private var preparingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("正在准备麦克风…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("首次使用需要授权麦克风与语音识别")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.record.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.record)
            }

            VStack(spacing: 8) {
                Text("无法开始录音")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
            }

            if !transcriber.segments.isEmpty {
                Text("已保留 \(transcriber.segments.count) 段转写内容")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 12) {
                if !transcriber.segments.isEmpty {
                    PillButton(title: "保存已有内容", icon: "checkmark") {
                        saveMeeting()
                    }
                }

                PillButton(
                    title: "重试",
                    icon: "arrow.clockwise",
                    kind: transcriber.segments.isEmpty ? .primary : .secondary
                ) {
                    Task {
                        await transcriber.start(
                            language: settings.languageCode,
                            offlineOnly: settings.offlineOnly
                        )
                    }
                }

                PillButton(title: "打开系统设置", icon: "gearshape", kind: .secondary) {
                    openSystemSettings()
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Actions

    private func finish() {
        guard transcriber.isRecording || !transcriber.segments.isEmpty else { return }

        if transcriber.isRecording {
            guard hasAnyContent else {
                Haptics.warning()
                showEmptyAlert = true
                return
            }
            transcriber.stop()
        }

        saveMeeting()
    }

    private func saveMeeting() {
        let transcript = transcriber.segments
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            Haptics.warning()
            showEmptyAlert = true
            return
        }

        let createdAt = transcriber.startDate ?? Date()
        let meeting = Meeting(
            title: AppFormat.defaultTitle(for: createdAt),
            createdAt: createdAt,
            duration: max(transcriber.elapsed, 1),
            transcript: transcript,
            segments: transcriber.segments,
            audioFileName: transcriber.audioFileName
        )

        modelContext.insert(meeting)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
