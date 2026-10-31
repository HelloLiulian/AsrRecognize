import SwiftData
import SwiftUI
import UIKit

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings

    @StateObject private var transcriber = LiveTranscriber()
    @StateObject private var local = LocalTranscriber()

    @State private var didStart = false
    @State private var showExitAlert = false
    @State private var showEmptyAlert = false

    private var usingLocal: Bool { settings.engine == .qwen }
    private var isRecording: Bool { usingLocal ? local.isRecording : transcriber.isRecording }
    private var isPaused: Bool { usingLocal ? local.isPaused : transcriber.isPaused }
    private var elapsed: TimeInterval { usingLocal ? local.elapsed : transcriber.elapsed }
    private var segments: [TranscriptSegment] { usingLocal ? local.segments : transcriber.segments }
    private var partialText: String { usingLocal ? local.partialText : transcriber.partialText }
    private var level: CGFloat { usingLocal ? local.level : transcriber.level }
    private var errorMessage: String? { usingLocal ? local.errorMessage : transcriber.errorMessage }
    private var startDate: Date? { usingLocal ? local.startDate : transcriber.startDate }
    private var audioFileName: String? { usingLocal ? local.audioFileName : transcriber.audioFileName }

    private var hasAnyContent: Bool {
        !segments.isEmpty
            || !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                topBar

                if isRecording || isPaused {
                    recordingContent
                } else if let message = errorMessage {
                    errorState(message)
                } else {
                    preparingState
                }
            }
            .alert("Keine Sprache erkannt", isPresented: $showEmptyAlert) {
                Button("Weiter aufnehmen", role: .cancel) {}
                Button("Verwerfen", role: .destructive) {
                    discardSession()
                    dismiss()
                }
            } message: {
                Text("Das Mikrofon hat keine verwertbare Sprache aufgenommen. Bitte näher am Mikrofon sprechen.")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .task {
            guard !didStart else { return }
            didStart = true
            await startSession()
        }
        .onDisappear {
            if isRecording {
                stopSession()
            }
        }
        .alert("Aufnahme beenden?", isPresented: $showExitAlert) {
            if hasAnyContent {
                Button("Speichern & schließen") { finish() }
            }
            Button("Verwerfen", role: .destructive) {
                discardSession()
                dismiss()
            }
            Button("Weiter aufnehmen", role: .cancel) {}
        } message: {
            Text("Die Aufnahme erscheint anschließend in der Liste.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                if isRecording || hasAnyContent {
                    showExitAlert = true
                } else {
                    discardSession()
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
            .accessibilityLabel("Schließen")

            Spacer()

            StatusPill(
                text: recorderStatusText,
                color: recorderStatusColor,
                pulse: isRecording && !isPaused
            )

            Spacer()

            Button {
                finish()
            } label: {
                Text("Fertig")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(!isRecording && segments.isEmpty)
            .opacity(isRecording || !segments.isEmpty ? 1 : 0.35)
            .accessibilityLabel("Beenden & speichern")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var recorderStatusText: String {
        if isRecording {
            return isPaused ? "PAUSIERT" : "REC"
        }
        return "BEREIT"
    }

    private var recorderStatusColor: Color {
        if isRecording {
            return isPaused ? Theme.warning : Theme.record
        }
        return Theme.textTertiary
    }

    // MARK: - Recording content

    private var recordingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            VStack(spacing: 16) {
                Text(AppFormat.clock(elapsed))
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                LiveWaveform(
                    level: level,
                    isActive: isRecording && !isPaused
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
        if usingLocal {
            if local.isDraining {
                return "Lokal · Abschluss läuft"
            }
            if !local.isPrepared {
                return local.statusText
            }
            return settings.languageCode.hasPrefix("en") ? "ENGLISH · QWEN3" : "Deutsch · Qwen3"
        }
        if settings.languageCode.hasPrefix("en") {
            return settings.offlineOnly ? "ENGLISH · OFFLINE" : "ENGLISH · LIVE"
        }
        return settings.offlineOnly ? "Deutsch · Offline" : "Deutsch · Live"
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Live-Transkript")
                Spacer()
                Text("\(segments.count) Abschnitte")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if segments.isEmpty && partialText.isEmpty {
                            Text("Sprechen Sie, der Text erscheint hier live…")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                        }

                        ForEach(segments) { segment in
                            TranscriptRow(segment: segment)
                        }

                        if !partialText.isEmpty {
                            TranscriptRow(
                                segment: TranscriptSegment(
                                    text: partialText,
                                    timestamp: elapsed
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
                .onChange(of: segments.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: partialText) { _, _ in
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
                if isPaused {
                    resumeSession()
                } else {
                    pauseSession()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.cardFill))
                    .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(isPaused ? "Aufnahme fortsetzen" : "Aufnahme pausieren")

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
            .accessibilityLabel("Beenden & speichern")
        }
    }

    // MARK: - Preparing / error

    private var preparingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)

            if usingLocal {
                Text(local.isPrepared ? "Mikrofon wird vorbereitet…" : "Lokales Modell wird geladen…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(local.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                if local.loadFraction > 0, local.loadFraction < 1 {
                    ProgressView(value: local.loadFraction)
                        .frame(maxWidth: 220)
                }
            } else {
                Text("Mikrofon wird vorbereitet…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("Beim ersten Start werden Mikrofon- und Spracherkennungszugriff angefragt.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
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
                Text("Aufnahme konnte nicht gestartet werden")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
            }

            if !segments.isEmpty {
                Text("\(segments.count) Abschnitte des Transkripts wurden gesichert.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 12) {
                if !segments.isEmpty {
                    PillButton(title: "Vorhandenes Transkript speichern", icon: "checkmark") {
                        saveMeeting()
                    }
                }

                if usingLocal {
                    PillButton(title: "System-Spracherkennung verwenden", icon: "waveform", kind: segments.isEmpty ? .primary : .secondary) {
                        switchToApple()
                    }
                }

                PillButton(
                    title: "Erneut versuchen",
                    icon: "arrow.clockwise",
                    kind: segments.isEmpty && !usingLocal ? .primary : .secondary
                ) {
                    Task {
                        await startSession()
                    }
                }

                PillButton(title: "iOS-Einstellungen öffnen", icon: "gearshape", kind: .secondary) {
                    openSystemSettings()
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Actions

    private func finish() {
        guard isRecording || !segments.isEmpty else { return }
        guard !(usingLocal && local.isDraining) else { return }

        if isRecording, usingLocal {
            Task { await finishLocal() }
            return
        }

        if isRecording {
            guard hasAnyContent else {
                Haptics.warning()
                showEmptyAlert = true
                return
            }
            stopSession()
        }

        saveMeeting()
    }

    private func finishLocal() async {
        guard !local.isDraining else { return }
        await local.stopAndFinish()
        guard !segments.isEmpty else {
            Haptics.warning()
            showEmptyAlert = true
            return
        }
        saveMeeting()
    }

    // MARK: - Session

    private func startSession() async {
        if usingLocal {
            await local.start(language: settings.languageCode)
        } else {
            await transcriber.start(language: settings.languageCode, offlineOnly: settings.offlineOnly)
        }
    }

    private func stopSession() {
        if usingLocal {
            local.stopImmediately()
        } else {
            transcriber.stop()
        }
    }

    private func pauseSession() {
        if usingLocal {
            local.pause()
        } else {
            transcriber.pause()
        }
    }

    private func resumeSession() {
        if usingLocal {
            local.resume()
        } else {
            transcriber.resume()
        }
    }

    private func discardSession() {
        if usingLocal {
            local.discard()
        } else {
            transcriber.discard()
        }
    }

    private func switchToApple() {
        local.discard()
        settings.engine = .apple
        Task {
            await transcriber.start(language: settings.languageCode, offlineOnly: settings.offlineOnly)
        }
    }

    private func saveMeeting() {
        let transcript = segments
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            Haptics.warning()
            showEmptyAlert = true
            return
        }

        let createdAt = startDate ?? Date()
        let meeting = Meeting(
            title: AppFormat.defaultTitle(for: createdAt),
            createdAt: createdAt,
            duration: max(elapsed, 1),
            transcript: transcript,
            segments: segments,
            audioFileName: audioFileName
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
