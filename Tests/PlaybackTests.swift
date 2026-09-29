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
