import Testing
@testable import TeleprompterCore

@Test func eachWordMovesTheReadingPositionWithinALine() {
    let layout = ReadingLayout(script: Script("alpha beta gamma delta"), fontSize: 36, width: 1000)
    #expect(layout.lines.count == 1)
    #expect(layout.offset(position: 1, lineHeight: 48) == 12)
    #expect(layout.offset(position: 2, lineHeight: 48) == 24)
    #expect(layout.offset(position: 2.5, lineHeight: 48) == 30)
}

@Test func scrollingRemainsContinuousWhenCrossingALineBoundary() {
    let layout = ReadingLayout(script: Script("alpha beta\ngamma delta"), fontSize: 36, width: 1000)
    #expect(layout.lines.count == 2)
    #expect(layout.offset(position: 1.99, lineHeight: 50) < 50)
    #expect(layout.offset(position: 2, lineHeight: 50) == 50)
    #expect(layout.offset(position: 2.01, lineHeight: 50) > 50)
    #expect(layout.offset(position: 2.01, lineHeight: 50) - layout.offset(position: 1.99, lineHeight: 50) < 1)
}

@Test func manualScrollingPreservesFractionalPositionAcrossUnequalLines() {
    let layout = ReadingLayout(script: Script("one two\nthree four five six\nseven eight nine"), fontSize: 36, width: 1000)
    for position in stride(from: 0.0, through: 9.0, by: 0.125) {
        let offset = layout.offset(position: position, lineHeight: 48)
        #expect(abs(layout.position(atOffset: offset, lineHeight: 48) - position) < 0.000001)
    }
    #expect(layout.scrolledPosition(from: 24, by: 48, lineHeight: 48) == 4)
    #expect(layout.scrolledPosition(from: 72, by: -48, lineHeight: 48) == 1)
}

@Test func manualScrollingStopsAtReadableEndsAndResumesFromTheNewPassage() {
    let script = Script("one two\nthree four five six\nseven eight nine")
    let layout = ReadingLayout(script: script, fontSize: 36, width: 1000)
    #expect(layout.scrolledPosition(from: 0, by: -500, lineHeight: 48) == 0)
    #expect(layout.scrolledPosition(from: 0, by: 500, lineHeight: 48) == 6)
    var playback = Playback()
    playback.seek(9, wordCount: 9)
    #expect(playback.state == .finished)
    playback.seek(layout.scrolledPosition(from: 144, by: -72, lineHeight: 48), wordCount: 9)
    #expect(playback.state == .paused)
    #expect(playback.position == 4)
    playback.play(now: 100, wordCount: 9)
    playback.tick(now: 104, layout: layout, wpm: 60, automatic: true)
    #expect(abs(layout.offset(position: playback.position, lineHeight: 48) - 88) < 0.000001)
    #expect(ReadingLayout(script: Script(""), fontSize: 36, width: 400)
        .scrolledPosition(from: 0, by: 100, lineHeight: 48) == 0)
}
