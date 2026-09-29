import AVFoundation
import Foundation
import Speech
import Testing
@testable import TeleprompterCore

// Opt-in because this may download Apple's English speech assets. The fixture is
// generated speech, never a recording of the user's microphone.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TELEPROMPTER_SPEECH_FIXTURE"] != nil), .timeLimit(.minutes(1)))
func onDeviceTranscriptionFeedsTheRealScriptMatcher() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["TELEPROMPTER_SPEECH_FIXTURE"])
    let script = Script("Today we are building a native teleprompter application for recording YouTube videos. Keep your eyes near the camera and speak at your own pace.")
    #expect(SpeechTranscriber.isAvailable)
    let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
    let locale = try #require(supported)
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let results = Task {
        var matcher = SpeechAlignment()
        var position = 0
        var finalText = ""
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            let segment = Int((result.range.start.seconds * 1000).rounded())
            if let next = matcher.consume(text, segment: segment, isFinal: result.isFinal, script: script, position: position) {
                position = max(position, next)
            }
            if result.isFinal { finalText += text + " " }
        }
        return (position, finalText)
    }
    do {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let (position, transcript) = try await results.value
        #expect(!transcript.isEmpty)
        #expect(position == script.tokens.count)
        print("On-device fixture transcript: \(transcript)")
    } catch {
        results.cancel()
        await analyzer.cancelAndFinishNow()
        throw error
    }
}
