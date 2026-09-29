import Foundation

/// Bounded rolling audio for Whisper. A new window retains two seconds of context;
/// timestamps exclude that overlap from the next transcript sent to the matcher.
public struct VoiceAudioWindow: Sendable {
    public private(set) var samples: [Float] = []
    public private(set) var segment = 0
    public private(set) var skipBefore: Float = 0
    private var sinceDecode = 0
    private var silence = 0
    private var hasSpeech = false
    public init() {}

    public mutating func append(_ audio: [Float]) {
        samples.append(contentsOf: audio)
        sinceDecode += audio.count
        let power = audio.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, audio.count))
        if power > 0.000004 { silence = 0; hasSpeech = true } else { silence += audio.count }
    }
    public var isBoundary: Bool { samples.count >= 192_000 || silence >= 10_400 }
    public var shouldDecode: Bool { hasSpeech && samples.count >= 12_800 && sinceDecode >= 9_600 }
    public var hasPendingSpeech: Bool { hasSpeech }
    public mutating func didDecode() { sinceDecode = 0 }
    public mutating func advance() {
        if silence >= 10_400 || !hasSpeech {
            samples.removeAll(keepingCapacity: true)
            skipBefore = 0
            hasSpeech = false
        } else {
            let overlap = min(32_000, samples.count)
            samples = Array(samples.suffix(overlap))
            skipBefore = Float(overlap) / 16_000
        }
        segment += 1
        sinceDecode = 0
        silence = 0
    }
}
