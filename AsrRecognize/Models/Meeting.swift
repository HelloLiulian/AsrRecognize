import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var segmentsData: Data
    var summaryData: Data?
    var audioFileName: String?
    var sourceRaw: String = MeetingSource.recording.rawValue
    var originalFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        transcript: String,
        segments: [TranscriptSegment] = [],
        audioFileName: String? = nil,
        source: MeetingSource = .recording,
        originalFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.segmentsData = (try? JSONEncoder().encode(segments)) ?? Data()
        self.summaryData = nil
        self.audioFileName = audioFileName
        self.sourceRaw = source.rawValue
        self.originalFileName = originalFileName
    }

    var source: MeetingSource {
        MeetingSource(rawValue: sourceRaw) ?? .recording
    }

    var segments: [TranscriptSegment] {
        (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
    }

    var summary: MeetingSummary? {
        get {
            guard let summaryData else { return nil }
            return try? JSONDecoder().decode(MeetingSummary.self, from: summaryData)
        }
        set {
            summaryData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var audioURL: URL? {
        guard let audioFileName, !audioFileName.isEmpty else { return nil }
        let url = AudioStorage.url(for: audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var snippet: String {
        let cleaned = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Kein Transkript vorhanden" : String(cleaned.prefix(90))
    }

    var hasSummary: Bool {
        guard let summary else { return false }
        return !summary.isEmpty
    }
}
