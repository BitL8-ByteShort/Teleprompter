import AVFoundation
import Foundation
import TeleprompterCore
import TeleprompterSpeech

@main struct VoiceEngineCheck {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let engine = VoiceEngine(rawValue: args[1]), engine != .apple else {
            print("Usage: swift run VoiceEngineCheck moonshine|parakeet|whisper fixture-16k-mono.wav [--download] [--fast] [--retake]")
            return
        }
        if args.contains("--download") {
            try await VoiceModelStore.download(engine) { print("DOWNLOAD: \($0)") }
        }
        let backend = VoiceBackends.make(engine)!
        do {
            let takes = args.contains("--retake") ? 2 : 1
            for take in 1...takes {
                let started = Date()
                print("TAKE \(take)")
                try await backend.prepare { event in
                    switch event {
                    case .status(let text): print("STATUS: \(text)")
                    case .failure(let text): print("FAILURE: \(text)")
                    case .transcript(let result): print("RESULT \(Date().timeIntervalSince(started))s segment=\(result.segment) final=\(result.isFinal): \(result.text)")
                    }
                }
                print("READY in \(Date().timeIntervalSince(started))s")
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]))
                guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 else {
                    throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use a 16 kHz mono fixture"])
                }
                let clock = ContinuousClock()
                let readingStart = clock.now
                var sent = 0
                while file.framePosition < file.length {
                    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1_600)!
                    try file.read(into: buffer)
                    let data = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                    try await backend.accept(data)
                    sent += data.count
                    if !args.contains("--fast") {
                        try await clock.sleep(until: readingStart.advanced(by: .seconds(Double(sent) / 16_000)))
                    }
                }
                // Flush trailing words as real silence, without recording a microphone.
                for _ in 0..<20 { try await backend.accept(Array(repeating: 0, count: 1_600)) }
                try await backend.finish()
                await backend.suspend()
            }
            await backend.stop()
            print("COMPLETE: \(engine.title)")
        } catch {
            await backend.stop()
            throw error
        }
    }
}
