import AVFoundation

/// Converts raw microphone buffers to 16kHz / mono / Float32 for VAD and recognition.
final class Audio16kConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if converter == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return [] }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return []
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, statusPointer in
            if consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPointer.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0,
              let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
