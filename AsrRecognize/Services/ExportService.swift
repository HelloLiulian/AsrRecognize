import Foundation

struct ExportPayload {
    var title: String
    var date: Date
    var duration: TimeInterval
    var transcript: String
    var summary: MeetingSummary?
}

enum FilenameSanitizer {
    static func sanitize(_ raw: String, fallback: String = "Protokoll", maxBytes: Int = 180) -> String {
        var value = raw.replacingOccurrences(
            of: "[/\\\\:*?\"<>|\\n\\r\\t]",
            with: "-",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        if value.count > 60 {
            value = String(value.prefix(60))
        }
        if value.utf8.count > maxBytes {
            var truncated = ""
            for character in value {
                let next = String(character)
                if truncated.utf8.count + next.utf8.count > maxBytes { break }
                truncated.append(character)
            }
            value = truncated
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        return value.isEmpty ? fallback : value
    }
}

enum ExportService {
    static func text(for payload: ExportPayload) -> String {
        var lines: [String] = []
        lines.append(payload.title)
        lines.append("")
        lines.append("Datum: \(AppFormat.meetingDate.string(from: payload.date))")
        lines.append("Dauer: \(AppFormat.duration(payload.duration))")
        lines.append("")

        if let summary = payload.summary, !summary.isEmpty {
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
                for item in summary.actionItems {
                    var parts = [item.task]
                    if let owner = item.owner, !owner.isEmpty {
                        parts.append("Verantwortlich: \(owner)")
                    }
                    if let deadline = item.deadline, !deadline.isEmpty {
                        parts.append("Frist: \(deadline)")
                    }
                    lines.append("- " + parts.joined(separator: " · "))
                }
                lines.append("")
            }
            if !summary.decisions.isEmpty {
                lines.append("## Beschlüsse")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
                lines.append("")
            }
        }

        lines.append("## Transkript")
        lines.append(payload.transcript)
        return lines.joined(separator: "\n")
    }

    static func writeText(for payload: ExportPayload) throws -> URL {
        let directory = try exportDirectory()
        let stamp = AppFormat.fileStamp.string(from: payload.date)
        // Empty titles fall back to the "Protokoll_" prefix instead of a duplicate segment.
        let title = FilenameSanitizer.sanitize(payload.title, fallback: "")
        let name = title.isEmpty ? "Protokoll_\(stamp).txt" : "Protokoll_\(title)_\(stamp).txt"
        let url = directory.appendingPathComponent(name)
        try text(for: payload).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func prepareAudio(source: URL, title: String) throws -> URL {
        let directory = try exportDirectory()
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let url = directory.appendingPathComponent("\(FilenameSanitizer.sanitize(title)).\(ext)")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try FileManager.default.linkItem(at: source, to: url)
        } catch {
            try FileManager.default.copyItem(at: source, to: url)
        }
        return url
    }

    private static func exportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
