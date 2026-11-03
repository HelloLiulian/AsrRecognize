import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var draftBaseURL = ""
    @State private var draftModel = ""
    @State private var draftKey = ""
    @State private var aiError: String?
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
                .readableWidth(760)
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
            syncDrafts()
        }
        .onChange(of: settings.provider) { _, _ in
            syncDrafts()
            aiError = nil
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

                Text("Einstellungen")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Fertig")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Einstellungen schließen")
        }
    }

    // MARK: - API

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "KI-ANBIETER")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(AIProvider.allCases) { provider in
                    providerRow(provider)
                }

                Divider()
                    .overlay(Theme.stroke)

                if settings.provider.requiresAPIKey {
                    labeledField("Basis-URL", text: $draftBaseURL, placeholder: settings.provider.defaultBaseURL, secure: false)
                    labeledField("Modell", text: $draftModel, placeholder: settings.provider.defaultModel, secure: false)
                    labeledField("API-Schlüssel", text: $draftKey, placeholder: "sk-…", secure: true)

                    if let aiError {
                        Text(aiError)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.record)
                    }

                    PillButton(title: "Speichern", icon: "checkmark") {
                        saveAI()
                    }

                    Text("Der Schlüssel wird pro Anbieter im Schlüsselbund gespeichert. Bei der KI-Zusammenfassung wird ausschließlich das Transkript an diesen Anbieter gesendet.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(3)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentBright)
                            .padding(.top, 1)
                        Text(settings.canSummarize
                             ? "Die lokale KI ist verfügbar. Es wird kein API-Schlüssel benötigt."
                             : AISummaryService.onDeviceAvailabilityMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                    }

                    Text("Das Transkript verlässt das Gerät nicht. Für lange Besprechungen wird es in Abschnitte aufgeteilt.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(3)
                }
            }
            .glassCard()
        }
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        Button {
            settings.provider = provider
            syncDrafts()
            aiError = nil
            Haptics.tap()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: settings.provider == provider ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(settings.provider == provider ? Theme.accentBright : Theme.textTertiary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Text(provider.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(2)

                    if let warning = provider.warning, settings.provider == provider {
                        Text(warning)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.warning)
                            .lineSpacing(2)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(settings.provider == provider ? .isSelected : [])
    }

    private func syncDrafts() {
        draftBaseURL = settings.aiBaseURL
        draftModel = settings.aiModel
        draftKey = settings.apiKey
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "KI-PROTOKOLL")

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatisch zusammenfassen")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Nach der Transkription automatisch zusammenfassen")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("Automatisch zusammenfassen", isOn: $settings.autoSummarize)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
                .padding(.vertical, 14)

                Divider()
                    .overlay(Theme.stroke)

                HStack {
                    Text("Anbieter")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(settings.provider.shortTitle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 14)

                Divider()
                    .overlay(Theme.stroke)

                HStack {
                    Text("Modell")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(settings.activeModelTitle)
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
            SectionLabel(text: "SPRACHERKENNUNG")

            VStack(alignment: .leading, spacing: 14) {
                Text("Sprache")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Picker("Sprache", selection: $settings.languageCode) {
                    Text("Deutsch").tag("de-DE")
                    Text("English").tag("en-US")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Verwendet die System-Spracherkennung von Apple. Mit „Nur auf dem Gerät“ bleibt die Erkennung offline; ohne diese Option kann Apple die Erkennung auf seinen Servern durchführen.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)

                Divider()
                    .overlay(Theme.stroke)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nur auf dem Gerät")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Audio verlässt das Gerät nicht. Die Genauigkeit kann etwas geringer sein.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("Nur auf dem Gerät", isOn: $settings.offlineOnly)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
            }
            .glassCard()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "ÜBER")

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Version")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(versionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Divider()
                    .overlay(Theme.stroke)

                Text("Audio und Transkripte bleiben auf dem Gerät. Nur bei aktivierter KI-Zusammenfassung wird das Transkript an den eingestellten Anbieter gesendet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.success)
                    Text("LOKAL ZUERST · DATENSCHUTZ")
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
                Text("Gespeichert")
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

    private func saveAI() {
        do {
            try settings.applyAIConfiguration(baseURL: draftBaseURL, model: draftModel, key: draftKey)
            draftBaseURL = settings.aiBaseURL
            draftModel = settings.aiModel
            draftKey = settings.apiKey
            aiError = nil
            Haptics.success()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                savedFlash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    savedFlash = false
                }
            }
        } catch {
            aiError = error.localizedDescription
            Haptics.warning()
        }
    }
}
