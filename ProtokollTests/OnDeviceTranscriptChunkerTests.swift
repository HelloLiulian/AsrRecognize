import XCTest
@testable import ProtokollLogic

final class OnDeviceTranscriptChunkerTests: XCTestCase {
    func testEmptyInput() {
        let (chunks, truncated) = OnDeviceTranscriptChunker.chunks(for: "   \n  ")
        XCTAssertTrue(chunks.isEmpty)
        XCTAssertFalse(truncated)
    }

    func testShortInputStaysWhole() {
        let (chunks, truncated) = OnDeviceTranscriptChunker.chunks(for: "Kurzes Transkript.")
        XCTAssertEqual(chunks, ["Kurzes Transkript."])
        XCTAssertFalse(truncated)
    }

    func testSplitsAtWordBoundary() {
        let text = String(repeating: "Wort ", count: 1_000)
        let (chunks, truncated) = OnDeviceTranscriptChunker.chunks(for: text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertFalse(truncated)
        XCTAssertFalse(chunks[0].hasSuffix("Wor"))
        XCTAssertFalse(chunks[1].hasPrefix(" "))
    }

    func testCapsAtMaxChunksAndReportsTruncation() {
        let text = String(repeating: "a", count: OnDeviceTranscriptChunker.chunkSize * (OnDeviceTranscriptChunker.maxChunks + 2))
        let (chunks, truncated) = OnDeviceTranscriptChunker.chunks(for: text)
        XCTAssertEqual(chunks.count, OnDeviceTranscriptChunker.maxChunks)
        XCTAssertTrue(truncated)
        XCTAssertEqual(chunks[0].count, OnDeviceTranscriptChunker.chunkSize)
    }

    func testExactChunkSizeIsNotTruncated() {
        let text = String(repeating: "b", count: OnDeviceTranscriptChunker.chunkSize)
        let (chunks, truncated) = OnDeviceTranscriptChunker.chunks(for: text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertFalse(truncated)
    }
}
