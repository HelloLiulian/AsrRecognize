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
    @State private var exportItem: ExportItem?
    @State private var exportError: String?

    struct ExportItem: Identifiable {
        let id = UUID()
        let url: URL
    }

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
                            (value: DetailTab.summary, label: "Zusammenfassung"),
                            (value: DetailTab.transcript, label: "Transkript")
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
        .alert("Besprechung löschen?", isPresented: $showDeleteAlert) {
            Button("Löschen", role: .destructive) {
                deleteMeeting()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Transkript, Protokoll und Aufnahme werden dauerhaft gelöscht.")
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
            .accessibilityLabel("Zurück")

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
            .accessibilityLabel("Protokoll teilen")

            Menu {
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

                Button {
                    copyTranscript()
                } label: {
                    Label("Transkript kopieren", systemImage: "doc.on.doc")
                }

                Button {
                    Task {
                        await generateSummary()
                    }
                } label: {
                    Label("Neu zusammenfassen", systemImage: "sparkles")
                }
                .disabled(isGenerating)

                Divider()

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Besprechung löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("Weitere Aktionen")
        }
    }

    // MARK: - Header

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Titel der Besprechung", text: $meeting.title, axis: .vertical)
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

            Text("Tippen Sie auf den Titel, um ihn zu bearbeiten")
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
            Label(AppFormat.characterCount(meeting.transcript.count), systemImage: "text.alignleft")
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
            .accessibilityLabel(audio.isPlaying ? "Wiedergabe pausieren" : "Aufnahme abspielen")

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
            truncated: meeting.transcript.count > AISummaryRequest.maxCharacters,
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
                SectionLabel(text: "Transkript")

                Spacer()

                Button {
                    copyTranscript()
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Transkript kopieren")
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
            Text("In die Zwischenablage kopiert")
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

        guard settings.hasAPIKey else {
            summaryError = "Bitte hinterlegen Sie zuerst einen API-Schlüssel in den Einstellungen."
            return
        }

        let transcript = meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            summaryError = "Für diese Besprechung liegt noch kein Transkript vor."
            return
        }

        isGenerating = true
        summaryError = nil
        defer { isGenerating = false }

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

    private var audioFileSize: Int64 {
        guard let url = meeting.audioURL else { return 0 }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

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
        lines.append("Datum: \(AppFormat.meetingDate.string(from: meeting.createdAt)) · Dauer: \(AppFormat.duration(meeting.duration))")
        lines.append("")

        if let summary = meeting.summary, !summary.isEmpty {
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
                let items = summary.actionItems.map { item -> String in
                    var parts = [item.task]
                    if let owner = item.owner, !owner.isEmpty {
                        parts.append("Verantwortlich: \(owner)")
                    }
                    if let deadline = item.deadline, !deadline.isEmpty {
                        parts.append("Frist: \(deadline)")
                    }
                    return "- " + parts.joined(separator: " · ")
                }
                lines.append(contentsOf: items)
                lines.append("")
            }

            if !summary.decisions.isEmpty {
                lines.append("## Beschlüsse")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
                lines.append("")
            }
        }

        lines.append("## Transkript")
        lines.append(meeting.transcript)

        return lines.joined(separator: "\n")
    }
}
