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
    #expect(alignment.consume("today", segment: 0, isFinal: false, script: script, position: 0) == 1)
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
    #expect(alignment.consume("welcome", segment: 0, isFinal: false, script: script, position: 0) == 1)
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

@Test func twoResumedWordsMoveWithoutWaitingForOldRecognitionErrorsToClear() {
    let script = Script("today we build a native application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("today we build", segment: 0, isFinal: false, script: script, position: 0) == 3)
    #expect(alignment.consume("today we build let me check the microphone a native", segment: 0,
                              isFinal: false, script: script, position: 3) == 5)
}

@Test func recentScriptWordsRecoverWhenReaderIsSeveralShortLinesAhead() {
    let script = Script("start with a plain paper sheet then fold both corners the edges meet neatly along the middle crease")
    var alignment = SpeechAlignment()
    // A recognizer retains unrelated words while the reader continues. The
    // exact recent phrase should catch up on this update, even ten words ahead.
    #expect(alignment.consume("sorry hang on let me just check this thing before continuing the edges meet", segment: 0,
                              isFinal: false, script: script, position: 0) == 13)
}

@Test func normalizedDuplicateAndAdlibCannotConsumeAnotherRepeatedPhrase() {
    let script = Script("today we build today we build a native application")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("today we build", segment: 0, isFinal: false, script: script, position: 0) == 3)
    #expect(alignment.consume("Today, we build!", segment: 0, isFinal: false, script: script, position: 3) == 3)
    let adlib = alignment.consume("Today, we build! let me check", segment: 0, isFinal: false, script: script, position: 3)
    #expect(adlib == nil || adlib == 3)
}

@Test func twoWordSuffixCannotSkipAheadToADifferentPassage() {
    let script = Script("today we build a native application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("unrelated commentary recording videos", segment: 0,
                              isFinal: false, script: script, position: 0) == nil)
}

@Test func volatileWrongEndingDoesNotBlockCorrectOpeningWords() {
    let script = Script("today we are building a native teleprompter application for recording videos")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("today we are going to", segment: 0, isFinal: false,
                              script: script, position: 0) == 3)
    #expect(alignment.consume("today we are building a new house", segment: 0, isFinal: false,
                              script: script, position: 3) == 5)
    #expect(alignment.consume("Today we are building a new house.", segment: 0, isFinal: false,
                              script: script, position: 5) == 5)
}

@Test func firstExactWordStartsFollowingAndCannotConsumeARepeatedPartial() {
    let script = Script("I bought a blue paper kite")
    var alignment = SpeechAlignment()
    #expect(alignment.consume("I", segment: 0, isFinal: false, script: script, position: 0) == 1)
    #expect(alignment.consume("I.", segment: 0, isFinal: false, script: script, position: 1) == 1)
    #expect(alignment.consume("blue", segment: 1, isFinal: false, script: script, position: 1) == nil)
    #expect(alignment.consume("bought", segment: 2, isFinal: false, script: script, position: 1) == 2)
}
