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
        #expect(next - previous <= height * 2.5 / 60 + 0.001)
        #expect(next <= height)
        previous = next
    }
    #expect(previous > height * 0.97)
}

@Test func recognitionBurstAndDelayedFrameCannotJumpSeveralLines() {
    var scroll = VoiceScroll()
    let next = scroll.advance(to: 200, elapsed: 0.5, lineHeight: 50)
    #expect(next > 0)
    #expect(next <= 50 * 2.5 / 30 + 0.001)
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
