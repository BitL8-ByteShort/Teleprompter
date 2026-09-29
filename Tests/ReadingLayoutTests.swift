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
