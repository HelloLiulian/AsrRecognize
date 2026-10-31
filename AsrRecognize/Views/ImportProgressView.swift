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
