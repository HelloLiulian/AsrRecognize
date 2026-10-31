import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    @State private var searchText = ""
    @State private var showRecorder = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var pendingDeletion: Meeting?

    private var filteredMeetings: [Meeting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.transcript.localizedCaseInsensitiveContains(query)
        }
    }

    private var weekMeetings: [Meeting] {
        meetings.filter {
            Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    private var weekDurationText: String {
        let total = weekMeetings.reduce(0) { $0 + $1.duration }
        return AppFormat.duration(total)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        searchField

                        if !meetings.isEmpty {
                            statsStrip
                        }

                        listSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                recordBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
            .fullScreenCover(isPresented: $showRecorder) {
                RecordingView()
                    .environmentObject(settings)
            }
            .alert("Besprechung löschen?", isPresented: deleteBinding, presenting: pendingDeletion) { meeting in
                Button("Löschen", role: .destructive) {
                    delete(meeting)
                }
                Button("Abbrechen", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { meeting in
                Text("Transkript, Protokoll und Aufnahme von „\(meeting.title)“ werden dauerhaft gelöscht.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ASR · MEETING NOTES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                Button {
                    Haptics.tap()
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.cardFill))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Einstellungen")
            }

            Text("Protokolle")
                .font(.system(size: 38, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 8) {
                Text(AppFormat.heroDate.string(from: Date()))
                Text("·")
                Text(AppFormat.weekLabel(Date()))
                Text("·")
                Text("\(meetings.count) Besprechungen")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField("Protokolle und Transkripte durchsuchen…", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Stats

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statItem(value: "\(weekMeetings.count)", label: "Diese Woche")
            statDivider
            statItem(value: weekDurationText, label: "Dauer diese Woche")
            statDivider
            statItem(value: "\(meetings.count)", label: "Gesamt")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 26)
    }

    // MARK: - List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: searchText.trimmingCharacters(in: .whitespaces).isEmpty ? "Letzte Besprechungen" : "Suchergebnisse")
                Spacer()
                if !filteredMeetings.isEmpty {
                    Text("\(filteredMeetings.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if filteredMeetings.isEmpty {
                EmptyStateView(
                    icon: meetings.isEmpty ? "waveform" : "magnifyingglass",
                    title: meetings.isEmpty ? "Noch keine Protokolle" : "Keine Treffer",
                    message: meetings.isEmpty
                        ? "Tippen Sie unten auf „Aufnahme starten“, um Ihre erste Besprechung aufzunehmen."
                        : "Versuchen Sie einen anderen Begriff oder leeren Sie die Suche."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredMeetings) { meeting in
                        NavigationLink {
                            MeetingDetailView(meeting: meeting)
                        } label: {
                            MeetingCardView(meeting: meeting)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = meeting
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Record bar

    private var recordBar: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.tap()
                showImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Audiodatei importieren")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Audiodatei importieren")

            Button {
                Haptics.tap()
                showRecorder = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("Aufnahme starten")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Theme.record, Theme.recordDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.record.opacity(0.32), radius: 24, y: 8)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Aufnahme starten")

            Text("Audio bleibt auf dem Gerät · Live-Transkript (\(settings.languageTitle))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.92), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func delete(_ meeting: Meeting) {
        AudioStorage.delete(named: meeting.audioFileName)
        modelContext.delete(meeting)
        try? modelContext.save()
        pendingDeletion = nil
        Haptics.success()
    }
}

// MARK: - Meeting card

struct MeetingCardView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(AppFormat.meetingDate.string(from: meeting.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if meeting.hasSummary {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
                }
            }

            Text(meeting.snippet)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Label(AppFormat.duration(meeting.duration), systemImage: "clock")
                if meeting.audioURL != nil {
                    Label("Audio", systemImage: "waveform")
                }
                Spacer()
                Text(AppFormat.characterCount(meeting.transcript.count))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
