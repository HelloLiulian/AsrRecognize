import SwiftUI

struct ImportSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let job: ImportJob
    let onStart: (ASREngine, String, String) -> Void

    @State private var title: String
    @State private var engine: ASREngine
    @State private var languageCode: String

    init(job: ImportJob, onStart: @escaping (ASREngine, String, String) -> Void) {
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
                .readableWidth(720)
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
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                onStart(engine, languageCode, trimmedTitle.isEmpty ? job.title : trimmedTitle)
                dismiss()
            }
            Button("Abbrechen") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
