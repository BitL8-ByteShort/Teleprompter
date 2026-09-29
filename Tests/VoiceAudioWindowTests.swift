import Testing
@testable import TeleprompterCore

@Test func whisperWindowStaysBoundedDuringLongSpeechAndKeepsOverlap() {
    var window = VoiceAudioWindow()
    for _ in 0..<3_000 {
        window.append(Array(repeating: 0.1, count: 1_600))
        #expect(window.samples.count <= 192_000)
        if window.shouldDecode { window.didDecode() }
        if window.isBoundary {
            window.advance()
            #expect(window.samples.count == 32_000)
            #expect(window.skipBefore == 2)
        }
    }
    #expect(window.segment > 20)
}

@Test func whisperSilenceDoesNotRequestRecognitionAndEndsAnUtterance() {
    var window = VoiceAudioWindow()
    for _ in 0..<20 {
        window.append(Array(repeating: 0, count: 1_600))
        #expect(!window.shouldDecode)
        if window.isBoundary { window.advance() }
    }
    window.append(Array(repeating: 0.1, count: 16_000))
    #expect(window.shouldDecode)
    window.didDecode()
    window.append(Array(repeating: 0, count: 11_200))
    #expect(window.isBoundary)
    window.advance()
    #expect(window.samples.isEmpty)
    #expect(!window.hasPendingSpeech)
    #expect(window.skipBefore == 0)
}
