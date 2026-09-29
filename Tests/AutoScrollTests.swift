import Testing
@testable import TeleprompterCore

private func unevenLayout() -> ReadingLayout {
    ReadingLayout(script: Script("one two three\nfour five six seven eight\nnine ten eleven twelve thirteen fourteen fifteen"), fontSize: 32, width: 2000)
}

@Test func autoScrollKeepsEqualSpeedAcrossUnequalLines() {
    let layout = unevenLayout()
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 0)
    // 15 words at 60 WPM take 15 seconds. Three 60-point lines
    // must therefore move at 12 points/sec, including across line breaks.
    for (time, expectedOffset) in [(1.0, 12.0), (6.0, 72.0), (12.0, 144.0)] {
        playback.tick(now: time, layout: layout, wpm: 60, automatic: true)
        #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - expectedOffset) < 0.000001)
    }
}

@Test func autoScrollHoldsThroughCountdownPauseAndManualRetake() {
    let layout = unevenLayout()
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 2)
    playback.tick(now: 1, layout: layout, wpm: 60, automatic: true)
    #expect(playback.position == 0)
    playback.tick(now: 2.5, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 6) < 0.000001)
    playback.pause()
    playback.tick(now: 100, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 6) < 0.000001)
    playback.play(now: 100, wordCount: 15, delay: 0)
    playback.tick(now: 101, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 18) < 0.000001)

    // Scroll into the middle of line two, then continue without a countdown.
    playback.seek(layout.scrolledPosition(from: 18, by: 75, lineHeight: 60), wordCount: 15)
    playback.play(now: 200, wordCount: 15, delay: 0)
    playback.tick(now: 201, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 105) < 0.000001)
}

@Test func autoScrollWPMChangesSpeedWithoutResettingPosition() {
    let layout = unevenLayout()
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 0)
    playback.tick(now: 4, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 48) < 0.000001)
    playback.tick(now: 5, layout: layout, wpm: 120, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 72) < 0.000001)
}

@Test(arguments: [[1.0 / 30], [1.0 / 60], [1.0 / 120], [0.008, 0.016, 0.1, 0.03]])
func autoScrollHasSteadyVelocityWithDifferentFrameTiming(intervals: [Double]) {
    let layout = unevenLayout()
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 0)
    var now = 0.0
    var frame = 0
    var previousOffset = 0.0
    while now < 14 {
        let next = min(14, now + intervals[frame % intervals.count])
        playback.tick(now: next, layout: layout, wpm: 60, automatic: true)
        let offset = layout.offset(position: playback.position, lineHeight: 60)
        // Compare distance directly; the final fractional frame can be only
        // a floating-point rounding remainder, too small for a speed quotient.
        #expect(abs((offset - previousOffset) - 12 * (next - now)) < 0.000001)
        previousOffset = offset
        now = next
        frame += 1
    }
    #expect(abs(previousOffset - 168) < 0.000001)
}

@Test func autoScrollFinishesAtWholeScriptWPMAndCanRestart() {
    let layout = unevenLayout()
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 0)
    playback.tick(now: 14.9, layout: layout, wpm: 60, automatic: true)
    #expect(playback.state == .playing)
    playback.tick(now: 15.001, layout: layout, wpm: 60, automatic: true)
    #expect(playback.state == .finished)
    #expect(playback.position == 15)
    #expect(layout.offset(position: playback.position, lineHeight: 60) == 180)
    playback.play(now: 100, wordCount: 15, delay: 0)
    #expect(playback.position == 0)
    playback.tick(now: 101, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 60) - 12) < 0.000001)
}

@Test func autoScrollAdaptsToReflowWithoutLosingThePassage() {
    let original = unevenLayout()
    let script = Script(original.lines.map(\.text).joined(separator: " "))
    let reflowed = ReadingLayout(script: script, fontSize: 40, width: 100000)
    var playback = Playback()
    playback.play(now: 0, wordCount: 15, delay: 0)
    playback.tick(now: 6, layout: original, wpm: 60, automatic: true)
    #expect(abs(playback.position - 4) < 0.000001)
    // Reflow to one line: same word remains current; pace recalibrates to it.
    #expect(abs(reflowed.offset(position: playback.position, lineHeight: 75) - 20) < 0.000001)
    playback.tick(now: 7, layout: reflowed, wpm: 60, automatic: true)
    #expect(abs(playback.position - 5) < 0.000001)
}
