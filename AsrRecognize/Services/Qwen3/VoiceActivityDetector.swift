import Foundation

/// 基于能量的流式 VAD：会议室等相对安静环境下可用，不依赖额外模型。
final class VoiceActivityDetector: @unchecked Sendable {
    struct Configuration {
        var sampleRate: Double = 16_000
        var frameDuration: Double = 0.02
        var startFrames = 3
        var endSilenceDuration: Double = 0.6
        var preRollDuration: Double = 0.3
        var minSegmentDuration: Double = 0.8
        var maxSegmentDuration: Double = 15
        var overlapDuration: Double = 0.2
        var thresholdMultiplier: Float = 3.0
        var minThreshold: Float = 0.008
        var noiseAdaptation: Float = 0.05
    }

    private let config: Configuration
    private let frameLength: Int
    private let endSilenceFrames: Int
    private let preRollCapacity: Int
    private let minSegmentSamples: Int
    private let maxSegmentSamples: Int
    private let overlapSamples: Int

    private var leftover: [Float] = []
    private var preRoll: [[Float]] = []
    private var segment: [[Float]] = []
    private var speechRun = 0
    private var silenceRun = 0
    private var isInSpeech = false
    private var noiseFloor: Float = 0.01
    private var calibrated = false
    private var segmentSampleCount = 0

    init(configuration: Configuration = Configuration()) {
        config = configuration
        frameLength = max(1, Int(configuration.sampleRate * configuration.frameDuration))
        endSilenceFrames = max(1, Int(configuration.endSilenceDuration / configuration.frameDuration))
        preRollCapacity = max(1, Int(configuration.preRollDuration / configuration.frameDuration))
        minSegmentSamples = Int(configuration.minSegmentDuration * configuration.sampleRate)
        maxSegmentSamples = Int(configuration.maxSegmentDuration * configuration.sampleRate)
        overlapSamples = Int(configuration.overlapDuration * configuration.sampleRate)
    }

    /// 输入任意长度的 16kHz 采样，返回本次凑齐的完整语音段。
    func feed(_ samples: [Float]) -> [[Float]] {
        leftover.append(contentsOf: samples)

        var completed: [[Float]] = []
        var index = 0
        while leftover.count - index >= frameLength {
            let frame = Array(leftover[index..<(index + frameLength)])
            index += frameLength
            if let finished = process(frame: frame) {
                completed.append(finished)
            }
        }
        if index > 0 {
            leftover.removeFirst(index)
        }
        return completed
    }

    /// 录音结束时取出最后一段未闭合语音。
    func flush() -> [Float]? {
        let merged = segment.flatMap { $0 }
        defer { resetSegment() }
        guard isInSpeech, merged.count >= minSegmentSamples else { return nil }
        return merged
    }

    private func process(frame: [Float]) -> [Float]? {
        let level = rms(of: frame)
        if !calibrated {
            noiseFloor = max(0.001, 0.7 * noiseFloor + 0.3 * level)
            calibrated = true
        }
        let threshold = max(config.minThreshold, noiseFloor * config.thresholdMultiplier)

        if !isInSpeech {
            if level < threshold {
                noiseFloor = (1 - config.noiseAdaptation) * noiseFloor + config.noiseAdaptation * level
            }
            preRoll.append(frame)
            if preRoll.count > preRollCapacity {
                preRoll.removeFirst()
            }

            if level >= threshold {
                speechRun += 1
                if speechRun >= config.startFrames {
                    isInSpeech = true
                    silenceRun = 0
                    segment = preRoll
                    segmentSampleCount = segment.reduce(0) { $0 + $1.count }
                    preRoll.removeAll(keepingCapacity: true)
                }
            } else {
                speechRun = 0
            }
            return nil
        }

        segment.append(frame)
        segmentSampleCount += frame.count

        if level >= threshold {
            silenceRun = 0
        } else {
            silenceRun += 1
        }

        let tooLong = segmentSampleCount >= maxSegmentSamples
        let ended = silenceRun >= endSilenceFrames
        guard tooLong || ended else { return nil }

        let merged = segment.flatMap { $0 }
        let overlap = tooLong ? Array(merged.suffix(overlapSamples)) : []
        resetSegment()

        if tooLong {
            segment = [overlap]
            segmentSampleCount = overlap.count
            isInSpeech = true
        }

        guard merged.count >= minSegmentSamples else { return nil }
        return merged
    }

    private func resetSegment() {
        segment = []
        segmentSampleCount = 0
        speechRun = 0
        silenceRun = 0
        isInSpeech = false
    }

    private func rms(of frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for value in frame {
            sum += value * value
        }
        return sqrt(sum / Float(frame.count))
    }
}
