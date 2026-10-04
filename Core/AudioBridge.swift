import AVFoundation
import Foundation

// The audio tap invokes this bridge serially. Its converter and meter state never
// cross onto the UI actor; only immutable levels and AnalyzerInput values do.
final class AudioBridge: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let deliver: @Sendable (AVAudioPCMBuffer) -> Bool
    let level: @Sendable (Float) -> Void
    let failure: @Sendable (String) -> Void
    private var meterFrames: UInt32 = 0
    private var failed = false

    init(from: AVAudioFormat, to: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Bool,
         level: @escaping @Sendable (Float) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw NSError(domain: "Teleprompter.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not prepare microphone audio for recognition."]) }
        self.converter = converter; self.format = to; self.deliver = deliver; self.level = level; self.failure = failure
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard !failed else { return }
        meterFrames += buffer.frameLength
        if meterFrames >= UInt32(buffer.format.sampleRate / 10), let samples = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            level(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60)))
            meterFrames = 0
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outputStatus in
            if supplied { outputStatus.pointee = .noDataNow; return nil }
            supplied = true; outputStatus.pointee = .haveData; return buffer
        }
        if status == .error {
            failed = true; failure("Could not convert microphone audio: \(error?.localizedDescription ?? "unknown error")"); return
        }
        if converted.frameLength > 0 {
            if !deliver(converted) {
                // A closed/full channel is handled by the session owner, not a
                // fatal conversion error. Ignore callbacks until its tap is removed.
                failed = true
            }
        }
    }
}
