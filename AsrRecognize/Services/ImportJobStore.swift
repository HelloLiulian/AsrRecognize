import Foundation

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
        let url = segmentsURL(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try encoder.encode(segment)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func segments(for id: UUID) -> [TranscriptSegment] {
        guard let data = try? Data(contentsOf: segmentsURL(for: id)) else { return [] }
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(TranscriptSegment.self, from: Data(line))
        }
    }

    func job(id: UUID) -> ImportJob? {
        guard let data = try? Data(contentsOf: stateURL(for: id)) else { return nil }
        return try? decoder.decode(ImportJob.self, from: data)
    }

    func resumableJobs() -> [ImportJob] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("state.json")),
                  let job = try? decoder.decode(ImportJob.self, from: data),
                  job.status != .finished else { return nil }
            return job
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}
