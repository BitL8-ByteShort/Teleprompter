import AVFoundation
import Foundation
import Synchronization
import Testing
import TeleprompterSpeech
@testable import TeleprompterCore

// Opt-in real-time generated-speech test. Uses installed models, no microphone,
// downloads, or speaker playback. Cold inference must finish before readiness.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TELEPROMPTER_LATENCY_FIXTURE"] != nil), .timeLimit(.minutes(1)))
func preparedVoiceBackendKeepsUpFromTheFirstSpokenWords() async throws {
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["TELEPROMPTER_LATENCY_FIXTURE"])
    let engine = try #require(VoiceEngine(rawValue: environment["TELEPROMPTER_LATENCY_ENGINE"] ?? "parakeet"))
    let backend = try #require(VoiceBackends.make(engine))
    let scriptText: String
    if let scriptPath = environment["TELEPROMPTER_LATENCY_SCRIPT"] {
        scriptText = try String(contentsOfFile: scriptPath, encoding: .utf8)
    } else {
        scriptText = "Today we are building a native teleprompter application for recording YouTube videos. Keep your eyes near the camera and speak at your own pace."
    }
    let script = Script(scriptText)
    let timing = Mutex((start: 0.0, first: Optional<Double>.none, firstMatch: Optional<Double>.none,
                        lastMatch: 0.0, longestGap: 0.0, peak: 0, alignment: SpeechAlignment(), position: 0))
    let preparationStart = ProcessInfo.processInfo.systemUptime
    try await backend.prepare { event in
        guard case .transcript(let result) = event, !result.text.isEmpty else { return }
        timing.withLock { state in
            let elapsed = ProcessInfo.processInfo.systemUptime - state.start
            if state.start > 0, state.first == nil {
                state.first = ProcessInfo.processInfo.systemUptime - state.start
            }
            if let next = state.alignment.consume(result.text, segment: result.segment, isFinal: result.isFinal,
                                                  script: script, position: state.position), next > state.position {
                state.firstMatch = state.firstMatch ?? (ProcessInfo.processInfo.systemUptime - state.start)
                state.longestGap = max(state.longestGap, elapsed - state.lastMatch)
                state.lastMatch = elapsed
                state.position = next
            }
            if environment["TELEPROMPTER_LATENCY_TRACE"] != nil {
                print("TRACE t=\(elapsed) position=\(state.position): \(result.text)")
            }
        }
    }
    let preparation = ProcessInfo.processInfo.systemUptime - preparationStart
    timing.withLock { $0.start = ProcessInfo.processInfo.systemUptime }
    let channel = AudioInputChannel<[Float]>(sampleRate: 16_000)
    let producer = Task.detached {
        defer { channel.finish(drain: true) }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        #expect(file.processingFormat.sampleRate == 16_000)
        #expect(file.processingFormat.channelCount == 1)
        let clock = ContinuousClock()
        let start = clock.now
        var sent = 0
        func send(_ samples: [Float]) throws {
            guard channel.offer(samples, frames: samples.count) == .accepted else {
                throw NSError(domain: "VoiceLatency", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Recognition fell behind live audio"])
            }
            timing.withLock { $0.peak = max($0.peak, channel.queuedFrames) }
            sent += samples.count
        }
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 400))
            try file.read(into: buffer)
            try send(Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))))
            try await clock.sleep(until: start.advanced(by: .seconds(Double(sent) / 16_000)))
        }
        for _ in 0..<80 {
            try Task.checkCancellation()
            try send(Array(repeating: 0, count: 400))
            try await clock.sleep(until: start.advanced(by: .seconds(Double(sent) / 16_000)))
        }
    }
    do {
        for await samples in channel.stream { try await backend.accept(samples) }
        try await producer.value
        try await backend.finish()
        await backend.stop()
    } catch {
        producer.cancel()
        channel.finish()
        _ = try? await producer.value
        await backend.stop()
        throw error
    }
    let measurement = timing.withLock { $0 }
    let first = try #require(measurement.first)
    let firstMatch = try #require(measurement.firstMatch)
    let backlog = Double(measurement.peak) / 16_000
    print("\(engine.title): preparation=\(preparation)s first transcript=\(first)s first match=\(firstMatch)s longest match gap=\(measurement.longestGap)s peak audio backlog=\(backlog)s followed words=\(measurement.position)/\(script.tokens.count)")
    #expect(first < 2)
    #expect(firstMatch < 2)
    #expect(backlog < 0.75)
    #expect(measurement.longestGap < 2)
    #expect(measurement.position == script.tokens.count)
}
