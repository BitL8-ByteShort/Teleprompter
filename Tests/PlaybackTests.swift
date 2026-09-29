import Testing
@testable import TeleprompterCore

@Test func elapsedTimeDeterminesProgress() {
    var playback = Playback()
    playback.play(now: 100, wordCount: 100, delay: 0)
    playback.tick(now: 110, wordCount: 100, wpm: 120, automatic: true)
    #expect(playback.position == 20)
    #expect(playback.state == .playing)
}

@Test func pausedTimeIsNotCountedOnResume() {
    var playback = Playback()
    playback.play(now: 0, wordCount: 100, delay: 0)
    playback.tick(now: 3, wordCount: 100, wpm: 120, automatic: true)
    playback.pause()
    playback.tick(now: 20, wordCount: 100, wpm: 120, automatic: true)
    #expect(playback.position == 6)
    playback.play(now: 30, wordCount: 100, delay: 0)
    playback.tick(now: 31, wordCount: 100, wpm: 120, automatic: true)
    #expect(playback.position == 8)
}

@Test func countdownThenFinish() {
    var playback = Playback()
    playback.play(now: 0, wordCount: 10)
    #expect(playback.state == .countdown)
    playback.tick(now: 2, wordCount: 10, wpm: 120, automatic: true)
    #expect(playback.position == 0)
    #expect(playback.countdown == 1)
    playback.tick(now: 4, wordCount: 10, wpm: 120, automatic: true)
    #expect(playback.position == 2)
    playback.tick(now: 10, wordCount: 10, wpm: 120, automatic: true)
    #expect(playback.position == 10)
    #expect(playback.state == .finished)
}

@Test func voiceModeDoesNotDriftDuringSilence() {
    var playback = Playback()
    playback.play(now: 0, wordCount: 20, delay: 0)
    playback.seek(5, wordCount: 20)
    playback.play(now: 0, wordCount: 20, delay: 0)
    playback.tick(now: 100, wordCount: 20, wpm: 130, automatic: false)
    #expect(playback.position == 5)
}

@Test func emptyScriptCannotStartAndSeekClamps() {
    var playback = Playback()
    playback.play(now: 0, wordCount: 0)
    #expect(playback.state == .stopped)
    playback.seek(500, wordCount: 20)
    #expect(playback.position == 20)
    playback.seek(-4, wordCount: 20)
    #expect(playback.position == 0)
}

@Test func voiceFinishWaitsForTheLastWordsToScrollOut() {
    var playback = Playback()
    playback.play(now: 0, wordCount: 10, delay: 0)
    playback.position = 10
    playback.tick(now: 1, wordCount: 10, wpm: 130, automatic: false, readyToFinish: false)
    #expect(playback.state == .playing)
    #expect(playback.position == 10)
    playback.tick(now: 2, wordCount: 10, wpm: 130, automatic: false, readyToFinish: true)
    #expect(playback.state == .finished)
}

@Test(arguments: [0, 1, 2, 3]) func countdownOptionsStartAtTheChosenTime(seconds: Int) {
    var playback = Playback()
    playback.play(now: 100, wordCount: 100, delay: Double(seconds))
    #expect(playback.state == (seconds == 0 ? .playing : .countdown))
    if seconds > 0 {
        playback.tick(now: 100 + Double(seconds) - 0.1, wordCount: 100, wpm: 60, automatic: true)
        #expect(playback.state == .countdown)
        #expect(playback.position == 0)
    }
    playback.tick(now: 100 + Double(seconds) + 0.5, wordCount: 100, wpm: 60, automatic: true)
    #expect(playback.state == .playing)
    #expect(abs(playback.position - 0.5) < 0.0001)
}

@Test func scrollingAnActiveTakeResumesAfterTheLastMomentumEventWithoutCountdown() {
    var playback = Playback()
    var gesture = ManualScrollSession()
    playback.play(now: 10, wordCount: 100, delay: 0)
    gesture.record(now: 11, wasRunning: playback.state == .playing)
    playback.seek(20.5, wordCount: 100)
    gesture.record(now: 11.25, wasRunning: false)
    #expect(gesture.shouldResume)
    let resumeDecision1 = gesture.takeResumeIfSettled(now: 11.4)
    #expect(!resumeDecision1)
    gesture.record(now: 11.5, wasRunning: false)
    let resumeDecision2 = gesture.takeResumeIfSettled(now: 11.7)
    #expect(!resumeDecision2)
    if gesture.takeResumeIfSettled(now: 11.9) {
        playback.play(now: 11.9, wordCount: 100, delay: 0)
    }
    #expect(playback.state == .playing)
    #expect(playback.countdown == 0)
    playback.tick(now: 12.9, wordCount: 100, wpm: 60, automatic: true)
    #expect(abs(playback.position - 21.5) < 0.0001)
    let resumeDecision3 = gesture.takeResumeIfSettled(now: 13)
    #expect(!resumeDecision3)
}

@Test func explicitPauseCancelsPendingResumeIncludingLaterMomentum() {
    var gesture = ManualScrollSession()
    gesture.record(now: 0, wasRunning: true)
    gesture.cancel() // Pause button, hide, edit, or a mode change.
    let resumeDecision4 = gesture.takeResumeIfSettled(now: 1)
    #expect(!resumeDecision4)
    gesture.record(now: 1.1, wasRunning: false)
    #expect(!gesture.shouldResume)
    let resumeDecision5 = gesture.takeResumeIfSettled(now: 2)
    #expect(!resumeDecision5)
    #expect(!gesture.isActive)
}

@Test func voiceResumesAtTheRepositionedPassageWithoutDriftingDuringSilence() {
    let script = Script("old opening words\n\nthis is the new passage to read")
    var playback = Playback()
    var alignment = SpeechAlignment()
    var gesture = ManualScrollSession()
    _ = alignment.consume("old opening words", segment: 0, isFinal: true, script: script, position: 0)
    gesture.record(now: 1, wasRunning: true)
    playback.seek(3, wordCount: script.tokens.count)
    alignment.reset()
    let resumeDecision6 = gesture.takeResumeIfSettled(now: 1.4)
    #expect(resumeDecision6)
    playback.play(now: 1.4, wordCount: script.tokens.count, delay: 0)
    playback.tick(now: 3, wordCount: script.tokens.count, wpm: 130, automatic: false)
    #expect(playback.position == 3)
    #expect(playback.state == .playing)
    #expect(alignment.consume("this is the new passage", segment: 0, isFinal: false,
                              script: script, position: Int(playback.position)) == 8)
}
