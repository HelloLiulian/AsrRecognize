import AVFoundation

/// 录音线程专用的写文件封装。
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
