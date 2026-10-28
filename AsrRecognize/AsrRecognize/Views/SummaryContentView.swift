import SwiftUI

struct SummaryContentView: View {
    let summary: MeetingSummary?
    let isGenerating: Bool
    let errorMessage: String?
    let hasAPIKey: Bool
    let truncated: Bool

    var onGenerate: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isGenerating {
                generatingCard
            } else if let errorMessage {
                errorCard(errorMessage)
            } else if let summary, !summary.isEmpty {
                summaryBody(summary)
            } else if !hasAPIKey {
                setupCard
            } else {
                generateCard
            }
        }
    }

    // MARK: - Summary

    private func summaryBody(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryHeader

            if !summary.overview.isEmpty {
                sectionCard(title: "会议摘要", icon: "text.quote") {
                    Text(summary.overview)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !summary.keyPoints.isEmpty {
                sectionCard(title: "关键要点", icon: "list.bullet") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22, alignment: .leading)
                                    .padding(.top, 3)

                                Text(point)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                sectionCard(title: "待办事项", icon: "checklist") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                            actionItemRow(item)
                        }
                    }
                }
            }

            if !summary.decisions.isEmpty {
                sectionCard(title: "会议决议", icon: "checkmark.seal") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, decision in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.success)
                                    .padding(.top, 1)

                                Text(decision)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if truncated {
                Text("转写内容较长，本次仅分析前 2 万字。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AI 会议纪要")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("由 DeepSeek 提炼")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            StatusPill(text: "DEEPSEEK", color: Theme.accentBright)
        }
        .padding(.horizontal, 2)
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        let owner = item.owner?.trimmingCharacters(in: .whitespaces) ?? ""
        let deadline = item.deadline?.trimmingCharacters(in: .whitespaces) ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                    .padding(.top, 2)

                Text(item.task)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !owner.isEmpty || !deadline.isEmpty {
                HStack(spacing: 8) {
                    if !owner.isEmpty {
                        metaChip(text: "负责人 · \(owner)")
                    }
                    if !deadline.isEmpty {
                        metaChip(text: "截止 · \(deadline)")
                    }
                }
                .padding(.leading, 23)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func metaChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - States

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.accent)
                Text("AI 正在整理纪要…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBar(height: 11)
                SkeletonBar(width: 240, height: 11)
                SkeletonBar(width: 280, height: 11)
                SkeletonBar(width: 160, height: 11)
            }

            Text("通常需要 10–30 秒")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("纪要生成失败")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                PillButton(title: "重试", icon: "arrow.clockwise", fullWidth: false, action: onGenerate)
                PillButton(title: "检查设置", icon: "gearshape", kind: .secondary, fullWidth: false, action: onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "key.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("连接 DeepSeek")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("开启 AI 纪要")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Text("填写 API Key 后，转写文本会发送给 DeepSeek，自动提炼摘要、关键要点与待办事项。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            PillButton(title: "配置 API Key", icon: "gearshape", action: onOpenSettings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("生成 AI 会议纪要")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("摘要 · 要点 · 待办 · 决议")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Text("基于本次会议的转写内容，由 DeepSeek 提炼结构化纪要。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            PillButton(title: "生成纪要", icon: "sparkles", action: onGenerate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
