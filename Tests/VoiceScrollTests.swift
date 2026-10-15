import Testing
@testable import TeleprompterCore

@Test func recognizedLineScrollsGraduallyInsteadOfSnapping() {
    var scroll = VoiceScroll()
    let height = 48.6
    let firstFrame = scroll.advance(to: height, elapsed: 1.0 / 60, lineHeight: height)
    #expect(firstFrame > 0)
    #expect(firstFrame < 1)
    var previous = firstFrame
    for _ in 1..<60 {
        let next = scroll.advance(to: height, elapsed: 1.0 / 60, lineHeight: height)
        #expect(next >= previous)
        #expect(next - previous < height * 0.1)
        #expect(next <= height)
        previous = next
    }
    #expect(previous > height * 0.97)
}

@Test func recognitionBurstAndDelayedFrameCannotJumpSeveralLines() {
    var scroll = VoiceScroll()
    let next = scroll.advance(to: 200, elapsed: 0.5, lineHeight: 50)
    #expect(next > 0)
    #expect(next < 50 * 0.4)
}

@Test func silenceSettlesAtLastRecognizedWordAndRetakeResetsMotion() {
    var scroll = VoiceScroll()
    for _ in 0..<240 { _ = scroll.advance(to: 20, elapsed: 1.0 / 60, lineHeight: 50) }
    #expect(abs(scroll.offset - 20) < 0.01)
    for _ in 0..<120 { #expect(scroll.advance(to: 20, elapsed: 1.0 / 60, lineHeight: 50) <= 20) }
    scroll.reset(to: 0)
    #expect(scroll.advance(to: 0, elapsed: 1.0 / 60, lineHeight: 50) == 0)
}

@Test func speechScrollHasConsistentMotionAtDifferentFrameRates() {
    func position(fps: Double) -> Double {
        var scroll = VoiceScroll()
        for _ in 0..<Int(fps / 2) { _ = scroll.advance(to: 40, elapsed: 1 / fps, lineHeight: 50) }
        return scroll.offset
    }
    #expect(abs(position(fps: 30) - position(fps: 120)) < 0.1)
}

@Test func severalRecognizedLinesCatchUpWithoutLeavingTheReaderBelowThePanel() {
    var scroll = VoiceScroll()
    let height = 43.2
    let target = height * 4
    var previous = 0.0
    for _ in 0..<30 {
        let next = scroll.advance(to: target, elapsed: 1.0 / 60, lineHeight: height)
        #expect(next >= previous && next <= target)
        #expect(next - previous <= height * 0.25)
        previous = next
    }
    // A four-line recognition burst must catch up within half a second.
    #expect(target - scroll.offset < height * 0.5)
}

@Test func narrowLinesDoNotAccumulateScrollLagDuringFastReading() {
    var scroll = VoiceScroll()
    let height = 43.2
    for frame in 1...180 {
        let target = Double(frame) / 60 * 3 * height
        _ = scroll.advance(to: target, elapsed: 1.0 / 60, lineHeight: height)
        if frame >= 60 { #expect(target - scroll.offset < height * 0.6) }
    }
}
