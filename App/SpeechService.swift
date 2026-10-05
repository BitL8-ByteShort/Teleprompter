import AVFoundation
import CoreAudio
import Speech
import OSLog

struct Microphone: Identifiable, Sendable {
    let id: String
    let name: String
    let deviceID: AudioDeviceID
}

enum VoiceError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
}

@MainActor
final class SpeechService {
    var onResult: ((String, Int, Bool) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onRecognitionReset: (() -> Void)?
    private var backend: (any VoiceBackend)?
    private var backendChoice: VoiceEngine?
    private var preparationTask: Task<Void, Error>?
    private var cleanupTask: Task<Void, Never>?
    private var pcmInput: AudioInputChannel<[Float]>?
    private var input: (any MicrophoneInput)?
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    private var analyzerInput: AudioInputChannel<AnalyzerInput>?
    private var recognitionRecoveryTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recovery = InputRecovery()
    private var analyzerFormat: AVAudioFormat?
    private var inputFormat: AVAudioFormat?
    private var selectedMicrophoneID = ""
    private var token = UUID()
    private let log = Logger(subsystem: "com.bitl8byteshort.Teleprompter", category: "AudioInput")

    func start(microphoneID: String, voiceEngine: VoiceEngine) async throws {
        stop()
        try await begin(microphoneID: microphoneID, voiceEngine: voiceEngine)
    }

    private func begin(microphoneID: String, voiceEngine: VoiceEngine) async throws {
        let sessionToken = token
        func check() throws {
            try Task.checkCancellation()
            guard sessionToken == token else { throw CancellationError() }
        }
        await cleanupTask?.value
        try check()
        onStatus?("Checking microphone access…")
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        try check()
        guard permitted else { throw VoiceError.unavailable("Microphone access is off. Enable Teleprompter in System Settings → Privacy & Security → Microphone, or use auto-scroll.") }
        let format = try await prepareRecognition(voiceEngine, sessionToken: sessionToken)
        try check()
        self.analyzerFormat = format
        self.selectedMicrophoneID = microphoneID
        let input = try InputOnlyCapture(device: InputDeviceStore.resolve(microphoneID))
        self.input = input
        try installInput(on: input, sessionToken: sessionToken)
        onStatus?("Listening · \(voiceEngine.title)")
    }

    private func prepareRecognition(_ choice: VoiceEngine, sessionToken: UUID) async throws -> AVAudioFormat {
        if backendChoice != choice {
            await backend?.stop()
            try Task.checkCancellation()
            guard token == sessionToken else { throw CancellationError() }
            backend = VoiceBackends.make(choice)
            backendChoice = choice
        }
        if let backend {
            self.backend = backend
            let task = Task { [weak self] in
                try await backend.prepare { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.token == sessionToken else { return }
                        switch event {
                        case .status(let text): self.onStatus?(text)
                        case .transcript(let result): self.onResult?(result.text, result.segment, result.isFinal)
                        case .failure(let text): self.onError?(text)
                        }
                    }
                }
            }
            preparationTask = task
            try await task.value
            try Task.checkCancellation()
            guard token == sessionToken else { throw CancellationError() }
            let input = AudioInputChannel<[Float]>(sampleRate: 16_000)
            pcmInput = input
            inputTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    for await samples in input.stream {
                        try Task.checkCancellation()
                        try await backend.accept(samples)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.inputFailed("Voice-follow stopped: \(error.localizedDescription)", sessionToken: sessionToken)
                }
            }
            return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        }
        func check() throws {
            try Task.checkCancellation()
            guard token == sessionToken else { throw CancellationError() }
        }
        guard SpeechTranscriber.isAvailable else { throw VoiceError.unavailable("On-device speech recognition is unavailable on this Mac. You can still use auto-scroll.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) else {
            throw VoiceError.unavailable("English speech recognition is unavailable. Use auto-scroll.")
        }
        try check()
        // Volatile results alone still batch several seconds of speech. Use the
        // smaller recognition context for live prompting; the script matcher
        // continues to reject uncertain or distant matches.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            onStatus?("Downloading English speech model…")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
        try check()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.unavailable("No supported speech audio format is available.")
        }
        try check()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        onStatus?("Preparing on-device recognition…")
        try await analyzer.prepareToAnalyze(in: format)
        try check()
        let input = AudioInputChannel<AnalyzerInput>(sampleRate: format.sampleRate)
        analyzerInput = input
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled, self?.token == sessionToken else { return }
                    let segment = Int((result.range.start.seconds * 1000).rounded())
                    self?.onResult?(String(result.text.characters), segment, result.isFinal)
                }
            } catch {
                guard !Task.isCancelled, self?.token == sessionToken else { return }
                self?.onError?("Speech recognition stopped: \(error.localizedDescription)")
            }
        }
        inputTask = Task.detached(priority: .userInitiated) { [weak self] in
            do { try await analyzer.start(inputSequence: input.stream) }
            catch {
                guard !Task.isCancelled else { return }
                await self?.inputFailed("Audio analysis stopped: \(error.localizedDescription)", sessionToken: sessionToken)
            }
        }
        return format
    }

    func stop() {
        token = UUID()
        recoveryTask?.cancel(); recoveryTask = nil
        recognitionRecoveryTask?.cancel(); recognitionRecoveryTask = nil
        recovery = InputRecovery()
        input?.stop(); input = nil
        analyzerInput?.finish(); analyzerInput = nil
        resultTask?.cancel(); resultTask = nil
        pcmInput?.finish(); pcmInput = nil
        let oldInput = inputTask
        let oldPreparation = preparationTask
        let oldBackend = backend
        let previousCleanup = cleanupTask
        oldInput?.cancel(); inputTask = nil
        oldPreparation?.cancel(); preparationTask = nil
        cleanupTask = Task {
            await previousCleanup?.value
            _ = try? await oldPreparation?.value
            await oldInput?.value
            await oldBackend?.suspend()
        }
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        analyzerFormat = nil
        inputFormat = nil
        onLevel?(0)
    }

    /// Called after pause when switching engines/modes or closing the app.
    /// Release the previous model before a subsequent start can load another.
    func releaseModel() {
        let oldBackend = backend
        let previousCleanup = cleanupTask
        backend = nil
        backendChoice = nil
        cleanupTask = Task {
            await previousCleanup?.value
            await oldBackend?.stop()
        }
    }

    private func installInput(on input: any MicrophoneInput, sessionToken: UUID) throws {
        guard let format = analyzerFormat else { throw CancellationError() }
        let natural = input.format
        guard natural.sampleRate > 0, natural.channelCount > 0 else {
            throw VoiceError.unavailable("The microphone has no audio input. Select another microphone.")
        }
        let analyzerInput = analyzerInput
        let pcmInput = pcmInput
        let bridge = try AudioBridge(from: natural, to: format, deliver: { [weak self] buffer in
            let delivery: AudioInputChannel<[Float]>.Delivery
            if let pcmInput, let data = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
                delivery = pcmInput.offer(samples, frames: samples.count)
            } else if let analyzerInput {
                switch analyzerInput.offer(AnalyzerInput(buffer: buffer), frames: Int(buffer.frameLength)) {
                case .accepted: delivery = .accepted
                case .overflow: delivery = .overflow
                case .closed: delivery = .closed
                }
            } else { return false }
            if delivery == .overflow {
                Task { @MainActor in self?.recoverRecognition(sessionToken: sessionToken) }
            }
            return delivery == .accepted
        },
            level: { [weak self] level in
                Task { @MainActor in guard self?.token == sessionToken else { return }; self?.onLevel?(level) }
            }, failure: { [weak self] message in
                Task { @MainActor in guard self?.token == sessionToken else { return }; self?.onError?(message) }
            })
        // The HAL callback executes outside MainActor; only UI updates hop back.
        try input.start(receive: { @Sendable buffer, _ in bridge.consume(buffer) }, failure: { [weak self] _ in
            Task { @MainActor in
                guard self?.token == sessionToken else { return }
                self?.scheduleInputRecovery(sessionToken: sessionToken)
            }
        })
        inputFormat = natural
    }

    private func inputFailed(_ message: String, sessionToken: UUID) {
        guard token == sessionToken else { return }
        onError?(message)
    }

    private func recoverRecognition(sessionToken: UUID) {
        guard token == sessionToken, let choice = backendChoice else { return }
        let microphoneID = selectedMicrophoneID
        log.notice("Audio backlog exceeded its bounded budget; restarting \(choice.title, privacy: .public) with reading position held")
        // Invalidate callbacks immediately, before awaiting the old inference.
        // stop() retains the selected model; begin() creates fresh stream state.
        stop()
        onRecognitionReset?()
        onStatus?("Reconnecting \(choice.title) · holding your place…")
        let recoveryToken = token
        recognitionRecoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await begin(microphoneID: microphoneID, voiceEngine: choice)
            } catch {
                guard !Task.isCancelled, token == recoveryToken else { return }
                onError?("Could not resume \(choice.title): \(error.localizedDescription)")
            }
            if token == recoveryToken { recognitionRecoveryTask = nil }
        }
    }

    private func scheduleInputRecovery(sessionToken: UUID) {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            // Only a fault in the selected input reaches this path. Coalesce it
            // and rebuild without resetting recognition or the reading position.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, token == sessionToken else { return }
            do {
                let device = try InputDeviceStore.resolve(selectedMicrophoneID)
                guard recovery.action(now: ProcessInfo.processInfo.systemUptime,
                    isRunning: false, formatUnchanged: false) != .stop else {
                    onError?("The selected microphone keeps changing. Choose another input or use auto-scroll.")
                    return
                }
                onStatus?("Reconnecting microphone…")
                input?.stop(); input = nil
                let replacement = try InputOnlyCapture(device: device)
                input = replacement
                try installInput(on: replacement, sessionToken: sessionToken)
                onStatus?("Listening on this Mac")
                log.info("Selected microphone recovered without changing playback or script position")
            } catch {
                onError?("Could not reconnect the selected microphone: \(error.localizedDescription)")
            }
        }
    }

    static func microphones() -> [Microphone] { InputDeviceStore.microphones() }
}
