import SwiftData
import SwiftUI
import UIKit

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings

    @Bindable var meeting: Meeting

    @StateObject private var audio = AudioPlayer()
    @State private var tab: DetailTab = .summary
    @State private var isGenerating = false
    @State private var summaryError: String?
    @State private var didAutoAttempt = false
    @State private var showDeleteAlert = false
    @State private var showSettings = false
    @State private var showCopied = false

    enum DetailTab: Hashable {
        case summary
        case transcript
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    titleBlock
                    metaRow

                    if meeting.audioURL != nil {
                        audioBar
                    }

                    CapsuleSegmentedControl(
                        selection: $tab,
                        options: [
                            (value: DetailTab.summary, label: "AI 纪要"),
                            (value: DetailTab.transcript, label: "原文")
                        ]
                    )
                    .padding(.top, 2)

                    if tab == .summary {
                        summarySection
                    } else {
                        transcriptSection
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            copiedToast
        }
        .onAppear {
            if let url = meeting.audioURL {
                audio.load(url: url)
            }
        }
        .onDisappear {
            audio.stop()
        }
        .task {
            guard !didAutoAttempt else { return }
            didAutoAttempt = true
            guard settings.autoSummarize,
                  meeting.summary == nil,
                  !meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  settings.hasAPIKey
            else { return }
            await generateSummary()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .alert("删除这场会议？", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                deleteMeeting()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("转写、纪要与录音将被永久删除，无法恢复。")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("返回")

            Spacer()

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享纪要")

            Menu {
                Button {
                    copyTranscript()
                } label: {
                    Label("复制原文", systemImage: "doc.on.doc")
                }

                Button {
                    Task {
                        await generateSummary()
                    }
                } label: {
                    Label("重新生成纪要", systemImage: "sparkles")
                }
                .disabled(isGenerating)

                Divider()

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("删除会议", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("更多操作")
        }
    }

    // MARK: - Header

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("会议标题", text: $meeting.title, axis: .vertical)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit {
                    try? modelContext.save()
                }

            Text("点击标题即可编辑")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 4)
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            Label(AppFormat.meetingDate.string(from: meeting.createdAt), systemImage: "calendar")
            Label(AppFormat.duration(meeting.duration), systemImage: "clock")
            Label("\(meeting.transcript.count) 字", systemImage: "text.alignleft")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    // MARK: - Audio

    private var audioBar: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                audio.toggle()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(audio.isPlaying ? "暂停播放" : "播放录音")

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * audio.progress), height: 3)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 10)

                HStack {
                    Text(AppFormat.clock(audio.progress * audio.duration))
                    Spacer()
                    Text(AppFormat.clock(audio.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Content

    private var summarySection: some View {
        SummaryContentView(
            summary: meeting.summary,
            isGenerating: isGenerating,
            errorMessage: summaryError,
            hasAPIKey: settings.hasAPIKey,
            truncated: meeting.transcript.count > 20000,
            onGenerate: {
                Task {
                    await generateSummary()
                }
            },
            onOpenSettings: {
                showSettings = true
            }
        )
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel(text: "原始转写")

                Spacer()

                Button {
                    copyTranscript()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制转写原文")
            }

            if meeting.segments.isEmpty {
                Text(meeting.transcript)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(meeting.segments) { segment in
                        TranscriptRow(segment: segment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var copiedToast: some View {
        if showCopied {
            Text("已复制到剪贴板")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.elevated))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    @MainActor
    private func generateSummary() async {
        guard !isGenerating else { return }

        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            summaryError = "请先在设置中填写 DeepSeek API Key。"
            return
        }

        let transcript = meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            summaryError = "这场会议还没有转写内容。"
            return
        }

        isGenerating = true
        summaryError = nil
        defer { isGenerating = false }

        do {
            let result = try await DeepSeekService.summarize(transcript: transcript, apiKey: key)
            meeting.summary = result
            try? modelContext.save()
            Haptics.success()
        } catch {
            summaryError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func copyTranscript() {
        UIPasteboard.general.string = meeting.transcript
        Haptics.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopied = false
            }
        }
    }

    private func deleteMeeting() {
        let fileName = meeting.audioFileName
        let context = modelContext
        let target = meeting
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            AudioStorage.delete(named: fileName)
            context.delete(target)
            try? context.save()
        }
    }

    private var shareText: String {
        var lines: [String] = []

        lines.append("# \(meeting.title)")
        lines.append("")
        lines.append("时间：\(AppFormat.meetingDate.string(from: meeting.createdAt)) · 时长：\(AppFormat.duration(meeting.duration))")
        lines.append("")

        if let summary = meeting.summary, !summary.isEmpty {
            if !summary.overview.isEmpty {
                lines.append("## 会议摘要")
                lines.append(summary.overview)
                lines.append("")
            }

            if !summary.keyPoints.isEmpty {
                lines.append("## 关键要点")
                lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
                lines.append("")
            }

            if !summary.actionItems.isEmpty {
                lines.append("## 待办事项")
                let items = summary.actionItems.map { item -> String in
                    var parts = [item.task]
                    if let owner = item.owner, !owner.isEmpty {
                        parts.append("负责人：\(owner)")
                    }
                    if let deadline = item.deadline, !deadline.isEmpty {
                        parts.append("截止：\(deadline)")
                    }
                    return "- " + parts.joined(separator: " · ")
                }
                lines.append(contentsOf: items)
                lines.append("")
            }

            if !summary.decisions.isEmpty {
                lines.append("## 会议决议")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
                lines.append("")
            }
        }

        lines.append("## 转写原文")
        lines.append(meeting.transcript)

        return lines.joined(separator: "\n")
    }
}
