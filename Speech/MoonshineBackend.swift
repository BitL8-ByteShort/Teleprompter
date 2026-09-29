import Foundation
@preconcurrency import MoonshineVoice

actor MoonshineBackend: VoiceBackend {
    private var transcriber: Transcriber?
    private var stream: MoonshineVoice.Stream?

    func prepare(report: @escaping @Sendable (VoiceEvent) -> Void) async throws {
        try VoiceModelStore.requireDownloaded(.moonshine)
        let directory = VoiceModelStore.folder(.moonshine)
        try Task.checkCancellation()
        if transcriber == nil {
            report(.status("Loading Moonshine Small…"))
            transcriber = try Transcriber(modelPath: directory.path, modelArch: .smallStreaming)
        }
        guard let transcriber else { return }
        let stream = try transcriber.createStream(updateInterval: 0.25)
        self.stream = stream
        stream.addListener { event in
            if let error = event as? TranscriptError {
                report(.failure(error.error.localizedDescription))
                return
            }
            let line = event.line
            guard !line.text.isEmpty else { return }
            report(.transcript(.init(line.text, segment: Int(truncatingIfNeeded: line.lineId), isFinal: line.isComplete)))
        }
        try Task.checkCancellation()
        try stream.start()
    }

    func accept(_ samples: [Float]) throws {
        try Task.checkCancellation()
        try stream?.addAudio(samples, sampleRate: 16_000)
    }
    func finish() throws { try stream?.stop() }
    func suspend() {
        // Dropping the stream closes it; calling close explicitly would free it twice.
        stream?.removeAllListeners()
        stream = nil
    }
    func stop() {
        suspend()
        transcriber = nil
    }
}
