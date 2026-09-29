import Testing
@testable import TeleprompterCore

@Test func unicodeAndParagraphNavigation() {
    let script = Script("Hello, café!\n\nDon't stop now.\n\nFinal paragraph.")
    #expect(script.tokens.map(\.normalized) == ["hello", "cafe", "dont", "stop", "now", "final", "paragraph"])
    #expect(script.paragraph(at: 3, direction: -1) == 2)
    #expect(script.paragraph(at: 2, direction: -1) == 0)
    #expect(script.paragraph(at: 1, direction: 1) == 2)
    #expect(script.word(atUTF16: 15) == 2)
}

@Test func revisedPartialDoesNotAdvanceRepeatedPhraseTwice() {
    let script = Script("welcome to the show welcome to the show and today we build")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("welcome to the show", segment: 0, isFinal: false, script: script, position: 0) == 4)
    let repeated = alignment.consume("welcome to the show", segment: 0, isFinal: true, script: script, position: 4)
    #expect(repeated == nil || repeated == 4)
    #expect(alignment.consume("welcome to the show and today", segment: 1, isFinal: true, script: script, position: 4) == 10)
}

@Test func pausesAndAdlibsHoldPosition() {
    let script = Script("today we build a native application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("", segment: 0, isFinal: false, script: script, position: 0) == nil)
    #expect(alignment.consume("let me get my coffee before continuing", segment: 1, isFinal: true, script: script, position: 0) == nil)
    #expect(alignment.consume("today we build", segment: 2, isFinal: true, script: script, position: 0) == 3)
}

@Test func smallOmissionAndRevisedRecognitionRecover() {
    let script = Script("today we build a wonderful native application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("today", segment: 0, isFinal: false, script: script, position: 0) == nil)
    #expect(alignment.consume("today we build a native application", segment: 0, isFinal: true, script: script, position: 0) == 7)
}

@Test func distantPhraseCannotCauseJumpAndRetakeCanReanchor() {
    let text = "first paragraph starts here\n\n" + Array(repeating: "filler", count: 100).joined(separator: " ") + "\n\nwelcome to the final scene"
    let script = Script(text)
    var alignment = SpeechAlignment()
    #expect(alignment.consume("welcome to the final scene", segment: 0, isFinal: true, script: script, position: 0) == nil)
    alignment.reset()
    #expect(alignment.consume("welcome to the final scene", segment: 0, isFinal: true, script: script, position: 104) == 109)
}

@Test func exactOpeningWordsRespondBeforeAWholePhraseIsFinished() {
    let script = Script("welcome to teleprompter welcome to another episode")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("welcome", segment: 0, isFinal: false, script: script, position: 0) == nil)
    #expect(alignment.consume("welcome to", segment: 0, isFinal: false, script: script, position: 0) == 2)
    #expect(alignment.consume("welcome to", segment: 0, isFinal: false, script: script, position: 2) == 2)
}

@Test func resumedScriptIsRecognizedPromptlyAfterAnAdlibInSameSegment() {
    let script = Script("today we build a native application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("today we build", segment: 0, isFinal: false, script: script, position: 0) == 3)
    #expect(alignment.consume("today we build let me grab my coffee first", segment: 0, isFinal: false, script: script, position: 3) == nil)
    let resumed = "today we build let me grab my coffee first a native application"
    #expect(alignment.consume(resumed, segment: 0, isFinal: false, script: script, position: 3) == 6)
    // Repeated partial results cannot eat a second occurrence of a phrase.
    #expect(alignment.consume(resumed, segment: 0, isFinal: true, script: script, position: 6) == 6)
}

@Test func cumulativeStreamingTranscriptFollowsALongTakeAndResetsForRetakes() {
    let words = (0..<500).map { "word\($0)" }
    let script = Script(words.joined(separator: " "))
    var alignment = SpeechAlignment()
    var position = 0
    for end in stride(from: 5, through: words.count, by: 5) {
        let partial = words.prefix(end).joined(separator: " ")
        let matched = alignment.consume(partial, segment: 0, isFinal: false, script: script, position: position)
        #expect(matched == end)
        position = matched ?? position
        #expect(alignment.consume(partial, segment: 0, isFinal: false, script: script, position: position) == position)
    }
    alignment.reset()
    #expect(alignment.consume(words[200..<205].joined(separator: " "), segment: 0,
                              isFinal: false, script: script, position: 200) == 205)
}
