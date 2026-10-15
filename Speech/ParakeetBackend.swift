import AVFoundation
import FluidAudio

actor ParakeetBackend: VoiceBackend {
    private var manager: StreamingEouAsrManager?
    private var report: (@Sendable (VoiceEvent) -> Void)?

    func prepare(report: @escaping @Sendable (VoiceEvent) -> Void) async throws {
        self.report = report
        try VoiceModelStore.requireDownloaded(.parakeet)
        if manager == nil {
            let chunkSize = StreamingChunkSize.ms320
            let loaded = StreamingEouAsrManager(chunkSize: chunkSize)
            report(.status("Loading Parakeet Realtime…"))
            try await loaded.loadModels(from: VoiceModelStore.folder(.parakeet).appendingPathComponent(Repo.parakeetEou320.folderName))
            // Core ML loads lazily: the first encoder/decoder predictions can
            // take seconds even after loadModels returns. Pay that cost before
            // microphone capture starts, then discard all warm-up stream state.
            report(.status("Preparing Parakeet Realtime…"))
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let silence = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(chunkSize.chunkSamples))!
            silence.frameLength = silence.frameCapacity
            silence.floatChannelData![0].initialize(repeating: 0, count: Int(silence.frameLength))
            _ = try await loaded.process(audioBuffer: silence)
            await loaded.reset()
            try Task.checkCancellation()
            manager = loaded
        }
        guard let manager else { return }
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
    func suspend() async {
        await manager?.setPartialTranscriptCallback { _ in }
        await manager?.reset()
        report = nil
    }
    func stop() async {
        await manager?.cleanup()
        manager = nil
        report = nil
    }
}
