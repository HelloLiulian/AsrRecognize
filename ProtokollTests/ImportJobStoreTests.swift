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
}
