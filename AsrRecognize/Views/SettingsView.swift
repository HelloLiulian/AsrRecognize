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
                                Text("Öffnen")
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
                    .accessibilityLabel(keyVisible ? "API-Schlüssel ausblenden" : "API-Schlüssel anzeigen")
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

                PillButton(title: "API-Schlüssel speichern", icon: "checkmark") {
                    saveKey()
                }

                Text("Der Schlüssel wird ausschließlich im Schlüsselbund gespeichert. Bei der KI-Zusammenfassung wird das Transkript an den konfigurierten Anbieter gesendet.")
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
                    Text("Modell")
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
            SectionLabel(text: "SPRACHERKENNUNG")

            VStack(alignment: .leading, spacing: 14) {
                Picker("Spracherkennung", selection: $settings.engine) {
                    Text("System-Spracherkennung").tag(ASREngine.apple)
                    Text("Lokales Qwen3").tag(ASREngine.qwen)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(engineDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)

                Divider()
                    .overlay(Theme.stroke)

                Text("Sprache")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Picker("Sprache", selection: $settings.languageCode) {
                    Text("Deutsch").tag("de-DE")
                    Text("English").tag("en-US")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

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

    private var engineDescription: String {
        if settings.engine == .qwen {
            guard LocalModelAssets.isBundled else {
                return "Diese App-Version enthält kein lokales Modell. Beim Start wird die System-Spracherkennung empfohlen."
            }
            return "Vollständig offline, Audio bleibt auf dem Gerät. Modell ca. 0,9 GB, erster Start ca. 1 Minute, nur iOS 18 und echtes Gerät."
        }
        return "Verwendet Apple Speech. Mit „Nur auf dem Gerät“ kann offline erkannt werden."
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
