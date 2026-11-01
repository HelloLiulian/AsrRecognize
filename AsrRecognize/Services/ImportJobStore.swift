import Foundation
import os

struct ImportJob: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case running
        case paused
        case finished
    }

    var id: UUID
    var audioFileName: String
    var originalFileName: String
    var title: String
    var engine: String
    var languageCode: String
    var offlineOnly: Bool
    var duration: TimeInterval
    var framesProcessed: Int64
    var sourceSampleRate: Double
    var status: Status
    var createdAt: Date
}

actor ImportJobStore {
    static let shared = ImportJobStore()

    private let base: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "Protokoll", category: "ImportJobStore")

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportJobs", isDirectory: true)
        base = root
    }

    private func directory(for id: UUID) -> URL {
        base.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func stateURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("state.json")
    }

    private func segmentsURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("segments.jsonl")
    }

    func create(_ job: ImportJob) throws {
        let dir = directory(for: job.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(job).write(to: stateURL(for: job.id), options: .atomic)
        FileManager.default.createFile(atPath: segmentsURL(for: job.id).path, contents: nil)
    }

    func update(_ job: ImportJob) throws {
        try FileManager.default.createDirectory(at: directory(for: job.id), withIntermediateDirectories: true)
        try encoder.encode(job).write(to: stateURL(for: job.id), options: .atomic)
    }

    func append(_ segment: TranscriptSegment, to id: UUID) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
        let url = segmentsURL(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try encoder.encode(segment)
        data.append(0x0A)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try truncateToCompleteLines(handle)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func replaceSegments(_ segments: [TranscriptSegment], for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
        var data = Data()
        for segment in segments {
            data.append(try encoder.encode(segment))
            data.append(0x0A)
        }
        try data.write(to: segmentsURL(for: id), options: .atomic)
    }

    private func truncateToCompleteLines(_ handle: FileHandle) throws {
        let end = try handle.seekToEnd()
        guard end > 0 else { return }
        let chunkSize: UInt64 = 4096
        var position = end
        while position > 0 {
            let readSize = min(chunkSize, position)
            try handle.seek(toOffset: position - readSize)
            guard let chunk = try handle.read(upToCount: Int(readSize)), !chunk.isEmpty else { break }
            if let lastNewline = chunk.lastIndex(of: 0x0A) {
                let validEnd = position - readSize + UInt64(lastNewline) + 1
                if validEnd < end { try handle.truncate(atOffset: validEnd) }
                return
            }
            position -= readSize
        }
        try handle.truncate(atOffset: 0)
    }

    func segments(for id: UUID) -> [TranscriptSegment] {
        guard let data = try? Data(contentsOf: segmentsURL(for: id)) else { return [] }
        var failures = 0
        let segments: [TranscriptSegment] = data.split(separator: 0x0A).compactMap { line in
            do {
                return try decoder.decode(TranscriptSegment.self, from: Data(line))
            } catch {
                failures += 1
                return nil
            }
        }
        if failures > 0 {
            logger.warning("Skipped \(failures) corrupt segment line(s) for job \(id.uuidString, privacy: .public)")
        }
        return segments
    }

    func job(id: UUID) -> ImportJob? {
        let url = stateURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("Could not read state for job \(id.uuidString, privacy: .public)")
            return nil
        }
        do {
            return try decoder.decode(ImportJob.self, from: data)
        } catch {
            logger.error("Could not decode state for job \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func resumableJobs() -> [ImportJob] {
        loadJobs().filter { $0.status != .finished }.sorted { $0.createdAt > $1.createdAt }
    }

    func finishedJobs() -> [ImportJob] {
        loadJobs().filter { $0.status == .finished }.sorted { $0.createdAt > $1.createdAt }
    }

    func pruneFinished() {
        for job in finishedJobs() {
            do {
                try FileManager.default.removeItem(at: directory(for: job.id))
            } catch {
                logger.error("Could not remove finished job \(job.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func loadJobs() -> [ImportJob] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { dir in
            let url = dir.appendingPathComponent("state.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url) else {
                logger.error("Could not read state at \(dir.lastPathComponent, privacy: .public)")
                return nil
            }
            do {
                return try decoder.decode(ImportJob.self, from: data)
            } catch {
                logger.error("Could not decode state at \(dir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}
