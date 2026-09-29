import Foundation

enum PlaybackState: String, Codable, Sendable { case stopped, countdown, playing, paused, finished }

/// Remembers playback intent across wheel ticks and trackpad momentum.
/// An explicit pause cancels that intent before any delayed resume can fire.
struct ManualScrollSession: Sendable {
    private var lastActivity: Double?
    private(set) var shouldResume = false
    var isActive: Bool { lastActivity != nil }

    mutating func record(now: Double, wasRunning: Bool) {
        if !isActive { shouldResume = wasRunning }
        lastActivity = now
    }

    mutating func takeResumeIfSettled(now: Double) -> Bool {
        guard let lastActivity, now - lastActivity >= 0.35 else { return false }
        let resume = shouldResume
        cancel()
        return resume
    }

    mutating func cancel() { lastActivity = nil; shouldResume = false }
}

struct Playback: Sendable {
    var state: PlaybackState = .stopped
    var position: Double = 0
    var countdown: Double = 0
    var lastTime: Double?
    mutating func play(now: Double, wordCount: Int, delay: Double = 3) {
        guard wordCount > 0 else { return }
        if position >= Double(wordCount) { position = 0 }
        lastTime = now
        countdown = max(0, delay)
        state = countdown > 0 ? .countdown : .playing
    }
    mutating func pause() {
        if state == .playing || state == .countdown { state = .paused }
        countdown = 0
        lastTime = nil
    }
    mutating func tick(now: Double, wordCount: Int, wpm: Double, automatic: Bool, readyToFinish: Bool = true) {
        var elapsed = max(0, now - (lastTime ?? now))
        lastTime = now
        if state == .countdown {
            let waiting = min(countdown, elapsed)
            countdown -= waiting
            elapsed -= waiting
            if countdown <= 0 { state = .playing }
        }
        guard state == .playing else { return }
        if automatic { position += elapsed * max(0, wpm) / 60 }
        if position >= Double(wordCount) {
            position = Double(wordCount)
            if readyToFinish { state = .finished }
        }
    }
    mutating func seek(_ position: Double, wordCount: Int) {
        pause()
        self.position = min(Double(wordCount), max(0, position))
        state = self.position >= Double(wordCount) && wordCount > 0 ? .finished : .paused
    }
}
