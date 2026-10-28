import Foundation

struct TranscriptSegment: Codable, Identifiable, Hashable {
    var id: UUID
    var text: String
    var timestamp: TimeInterval

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}
