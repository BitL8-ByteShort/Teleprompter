import Foundation

public enum VoiceEngine: String, Codable, CaseIterable, Sendable {
    case moonshine, parakeet, whisper, apple

    public var title: String {
        switch self {
        case .moonshine: "Moonshine Small"
        case .parakeet: "Parakeet Realtime"
        case .whisper: "Whisper Turbo"
        case .apple: "Apple Speech"
        }
    }

    public var detail: String {
        switch self {
        case .moonshine: "Small Streaming · English · recommended starting point for 8 GB and 16 GB Macs."
        case .parakeet: "EOU 120M · English · live streaming with 320 ms audio steps."
        case .whisper: "Large v3 Turbo · English recognition · compressed model. Best tried on 16 GB or more."
        case .apple: "Built-in macOS recognition · English · system-managed model."
        }
    }
}
