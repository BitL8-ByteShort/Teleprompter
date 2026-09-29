import AVFoundation
import FluidAudio

actor ParakeetBackend: VoiceBackend {
    private var manager: StreamingEouAsrManager?
    private var report: (@Sendable (VoiceEvent) -> Void)?

    func prepare(report: @escaping @Sendable (VoiceEvent) -> Void) async throws {
        self.report = report
        let manager = StreamingEouAsrManager(chunkSize: .ms320)
        self.manager = manager
        try VoiceModelStore.requireDownloaded(.parakeet)
        report(.status("Loading Parakeet Realtime…"))
        try await manager.loadModels(from: VoiceModelStore.folder(.parakeet).appendingPathComponent(Repo.parakeetEou320.folderName))
        try Task.checkCancellation()
        // FluidAudio returns a cumulative transcript, including across EOU events.
        // Keep one identity until stop/reset, so repeated partials cannot re-advance.
        await manager.setPartialTranscriptCallback { text in
            report(.transcript(.init(text, segment: 0, isFinal: false)))
        }
    }

    func accept(_ samples: [Float]) async throws {
        try Task.checkCancellation()
        guard let manager, let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { buffer.floatChannelData![0].update(from: base, count: samples.count) }
        }
        _ = try await manager.process(audioBuffer: buffer)
    }
    func finish() async throws {
        if let manager { report?(.transcript(.init(try await manager.finish(), segment: 0, isFinal: true))) }
    }
    func stop() async {
        await manager?.cleanup()
        manager = nil
        report = nil
    }
}
