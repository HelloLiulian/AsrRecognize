import Foundation
import XCTest
@testable import ProtokollLogic

final class ImportJobStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ImportJobStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ImportJobStore(baseDirectory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeJob() -> ImportJob {
        ImportJob(
            id: UUID(),
            audioFileName: "audio.m4a",
            originalFileName: "Original.m4a",
            title: "Teamrunde",
            engine: "qwen",
            languageCode: "de-DE",
            offlineOnly: true,
            duration: 120,
            framesProcessed: 0,
            sourceSampleRate: 16_000,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_793_000_000)
        )
    }

    func testRoundTripAndAppend() async throws {
        let job = makeJob()
        try await store.create(job)
        let first = TranscriptSegment(text: "Hallo", timestamp: 1)
        let second = TranscriptSegment(text: "Welt", timestamp: 2)
        try await store.append(first, to: job.id)
        try await store.append(second, to: job.id)

        var updated = job
        updated.framesProcessed = 32_000
        try await store.update(updated)

        let loaded = await store.job(id: job.id)
        XCTAssertEqual(loaded?.framesProcessed, 32_000)
        let segments = await store.segments(for: job.id)
        XCTAssertEqual(segments.map(\.text), ["Hallo", "Welt"])
    }

    func testResumableJobsExcludeFinished() async throws {
        var running = makeJob()
        running.status = .running
        var finished = makeJob()
        finished.status = .finished
        try await store.create(running)
        try await store.create(finished)

        let jobs = await store.resumableJobs()
        XCTAssertEqual(jobs.map(\.id), [running.id])
    }

    func testDeleteRemovesDirectory() async throws {
        let job = makeJob()
        try await store.create(job)
        await store.delete(id: job.id)
        let jobs = await store.resumableJobs()
        XCTAssertTrue(jobs.isEmpty)
    }

    func testAppendRecoversFromPartialTrailingLine() async throws {
        let job = makeJob()
        try await store.create(job)
        let first = TranscriptSegment(text: "Hallo", timestamp: 1)
        try await store.append(first, to: job.id)

        let segmentsURL = directory
            .appendingPathComponent(job.id.uuidString, isDirectory: true)
            .appendingPathComponent("segments.jsonl")
        let handle = try FileHandle(forWritingTo: segmentsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"broken".utf8))

        let second = TranscriptSegment(text: "Welt", timestamp: 2)
        try await store.append(second, to: job.id)

        let segments = await store.segments(for: job.id)
        XCTAssertEqual(segments.map(\.text), ["Hallo", "Welt"])
    }

    func testReplaceSegmentsRewritesLogAndKeepsAppending() async throws {
        let job = makeJob()
        try await store.create(job)
        try await store.append(TranscriptSegment(text: "Eins", timestamp: 1), to: job.id)
        try await store.append(TranscriptSegment(text: "Zwei", timestamp: 2), to: job.id)

        let kept = await store.segments(for: job.id).filter { $0.text == "Eins" }
        try await store.replaceSegments(kept, for: job.id)
        var texts = await store.segments(for: job.id).map(\.text)
        XCTAssertEqual(texts, ["Eins"])

        try await store.append(TranscriptSegment(text: "Drei", timestamp: 3), to: job.id)
        texts = await store.segments(for: job.id).map(\.text)
        XCTAssertEqual(texts, ["Eins", "Drei"])
    }

    func testPruneFinishedRemovesOnlyFinishedJobs() async throws {
        var running = makeJob()
        running.status = .running
        var finished = makeJob()
        finished.status = .finished
        try await store.create(running)
        try await store.create(finished)
        try await store.append(TranscriptSegment(text: "Fertig", timestamp: 1), to: finished.id)

        await store.pruneFinished()

        let finishedJobs = await store.finishedJobs()
        XCTAssertTrue(finishedJobs.isEmpty)
        let resumable = await store.resumableJobs()
        XCTAssertEqual(resumable.map(\.id), [running.id])

        let finishedDirectory = directory.appendingPathComponent(finished.id.uuidString, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finishedDirectory.path))
        let runningDirectory = directory.appendingPathComponent(running.id.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runningDirectory.path))
    }

    func testSegmentsSkipsCorruptLine() async throws {
        let job = makeJob()
        try await store.create(job)

        let encoder = JSONEncoder()
        var contents = Data()
        contents.append(try encoder.encode(TranscriptSegment(text: "Hallo", timestamp: 1)))
        contents.append(0x0A)
        contents.append(Data("kein json".utf8))
        contents.append(0x0A)
        contents.append(try encoder.encode(TranscriptSegment(text: "Welt", timestamp: 2)))
        contents.append(0x0A)

        let segmentsURL = directory
            .appendingPathComponent(job.id.uuidString, isDirectory: true)
            .appendingPathComponent("segments.jsonl")
        try contents.write(to: segmentsURL)

        let segments = await store.segments(for: job.id)
        XCTAssertEqual(segments.map(\.text), ["Hallo", "Welt"])
    }
}
