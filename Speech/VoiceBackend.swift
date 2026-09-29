import Foundation
#if canImport(TeleprompterCore)
import TeleprompterCore
#endif

public struct RecognizedPassage: Sendable {
    public let text: String
    public let segment: Int
    public let isFinal: Bool
    public init(_ text: String, segment: Int, isFinal: Bool) {
        self.text = text; self.segment = segment; self.isFinal = isFinal
    }
}

public enum VoiceEvent: Sendable {
    case status(String)
    case transcript(RecognizedPassage)
    case failure(String)
}

/// Called serially from a worker, never from the microphone tap or the UI actor.
/// Audio is mono Float32 at 16 kHz and is never written to disk.
public protocol VoiceBackend: Actor {
    func prepare(report: @escaping @Sendable (VoiceEvent) -> Void) async throws
    func accept(_ samples: [Float]) async throws
    func finish() async throws
    func suspend() async
    func stop() async
}

public extension VoiceBackend {
    func suspend() async { await stop() }
}

public enum VoiceBackends {
    public static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Teleprompter/Models", isDirectory: true)
    }

    public static func make(_ engine: VoiceEngine) -> (any VoiceBackend)? {
        switch engine {
        case .moonshine: MoonshineBackend()
        case .parakeet: ParakeetBackend()
        case .whisper: WhisperBackend()
        case .apple: nil
        }
    }
}
