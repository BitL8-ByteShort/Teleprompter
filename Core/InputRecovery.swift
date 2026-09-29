import Foundation

enum InputRecoveryAction: Equatable {
    case keepRunning
    case rebuild
    case stop
}

/// An audio-engine configuration notification is a request to re-check its
/// format and running state, not proof that the microphone is unusable.
struct InputRecovery {
    private var windowStart: Double?
    private var attempts = 0

    mutating func action(now: Double, isRunning: Bool, formatUnchanged: Bool) -> InputRecoveryAction {
        if isRunning && formatUnchanged { return .keepRunning }
        if windowStart == nil || now - (windowStart ?? now) >= 5 {
            windowStart = now
            attempts = 0
        }
        guard attempts < 3 else { return .stop }
        attempts += 1
        return .rebuild
    }
}
