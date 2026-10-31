import AVFoundation

/// File-writing wrapper dedicated to the recording thread.
final class AudioFileSink: @unchecked Sendable {
    private var file: AVAudioFile?

    func open(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        try? file?.write(from: buffer)
    }

    func close() {
        file = nil
    }
}
