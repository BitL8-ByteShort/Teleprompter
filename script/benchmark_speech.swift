// Run with generated speech only. Streams it at real-time pace, without using
// speakers or microphone, to compare recognition latency on this Mac.
import AVFoundation
import Foundation
import Speech

@main struct SpeechBenchmark {
    static func main() async throws {
        let path = CommandLine.arguments[1]
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))!
        for fast in [false, true] {
            let options: Set<SpeechTranscriber.ReportingOption> = fast ? [.volatileResults, .fastResults] : [.volatileResults]
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: options, attributeOptions: [.audioTimeRange])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatInt16, interleaved: false)
            let format = file.processingFormat
            try await analyzer.prepareToAnalyze(in: format)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let began = ProcessInfo.processInfo.systemUptime
            let reader = Task {
                var partials = 0
                var first: Double?
                var firstAdvance: Double?
                var lastAdvance = 0.0
                var longestGap = 0.0
                var matcher = SpeechAlignment()
                let script = Script("Today we are building a native teleprompter application for recording YouTube videos. Keep your eyes near the camera and speak at your own pace.")
                var position = 0
                for try await result in transcriber.results {
                    let elapsed = ProcessInfo.processInfo.systemUptime - began
                    if !result.isFinal {
                        first = first ?? elapsed
                        partials += 1
                    }
                    let text = String(result.text.characters)
                    let segment = Int((result.range.start.seconds * 1000).rounded())
                    if let next = matcher.consume(text, segment: segment, isFinal: result.isFinal, script: script, position: position) {
                        if next > position {
                            firstAdvance = firstAdvance ?? elapsed
                            longestGap = max(longestGap, elapsed - lastAdvance)
                            lastAdvance = elapsed
                            print("\(fast ? "fast" : "baseline") t=\(String(format: "%.2f", elapsed)) word=\(next)")
                        }
                        position = max(position, next)
                    }
                }
                print("\(fast ? "fast" : "baseline"): firstPartial=\(String(format: "%.2f", first ?? -1))s firstAdvance=\(String(format: "%.2f", firstAdvance ?? -1))s longestAdvanceGap=\(String(format: "%.2f", longestGap))s partials=\(partials) words=\(position)/\(script.tokens.count)")
            }
            let analysis = Task { try await analyzer.start(inputSequence: stream) }
            let chunk = AVAudioFrameCount(format.sampleRate / 10)
            while file.framePosition < file.length {
                let offset = file.framePosition
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
                try file.read(into: buffer)
                let deadline = Double(offset + Int64(buffer.frameLength)) / format.sampleRate
                let delay = deadline - (ProcessInfo.processInfo.systemUptime - began)
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: CMTime(value: offset, timescale: CMTimeScale(format.sampleRate))))
            }
            continuation.finish()
            try await analysis.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await reader.value
        }
    }
}
