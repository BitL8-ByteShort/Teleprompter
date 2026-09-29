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
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var configurationObserver: NSObjectProtocol?
    private var recoveryTask: Task<Void, Never>?
    private var recovery = InputRecovery()
    private var analyzerFormat: AVAudioFormat?
    private var inputFormat: AVAudioFormat?
    private var selectedMicrophoneID = ""
    private var token = UUID()
    private let log = Logger(subsystem: "com.bitl8byteshort.Teleprompter", category: "AudioInput")

    func start(microphoneID: String) async throws {
        stop()
        let sessionToken = token
        func check() throws {
            try Task.checkCancellation()
            guard sessionToken == token else { throw CancellationError() }
        }
        onStatus?("Checking microphone access…")
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        try check()
        guard permitted else { throw VoiceError.unavailable("Microphone access is off. Enable Teleprompter in System Settings → Privacy & Security → Microphone, or use auto-scroll.") }
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
        let engine = AVAudioEngine()
        self.engine = engine
        self.analyzerFormat = format
        self.selectedMicrophoneID = microphoneID
        let input = engine.inputNode
        if !microphoneID.isEmpty {
            guard var device = Self.microphones().first(where: { $0.id == microphoneID })?.deviceID,
                  let unit = input.audioUnit else {
                throw VoiceError.unavailable("The selected microphone is disconnected. Select an available microphone.")
            }
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw VoiceError.unavailable("Could not open the selected microphone (\(status)).") }
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation
        try installTap(on: engine, sessionToken: sessionToken)
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
        inputTask = Task { [weak self] in
            do { try await analyzer.start(inputSequence: stream) }
            catch {
                guard !Task.isCancelled, self?.token == sessionToken else { return }
                self?.onError?("Audio analysis stopped: \(error.localizedDescription)")
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.token == sessionToken else { return }
                self?.scheduleInputRecovery(sessionToken: sessionToken)
            }
        }
        engine.prepare()
        try engine.start()
        onStatus?("Listening on this Mac")
    }

    func stop() {
        token = UUID()
        recoveryTask?.cancel(); recoveryTask = nil
        recovery = InputRecovery()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        tapInstalled = false
        engine = nil
        continuation?.finish(); continuation = nil
        resultTask?.cancel(); resultTask = nil
        inputTask?.cancel(); inputTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        analyzerFormat = nil
        inputFormat = nil
        onLevel?(0)
    }

    private func installTap(on engine: AVAudioEngine, sessionToken: UUID) throws {
        guard let format = analyzerFormat, let continuation else { throw CancellationError() }
        let input = engine.inputNode
        let natural = input.outputFormat(forBus: 0)
        guard natural.sampleRate > 0, natural.channelCount > 0 else {
            throw VoiceError.unavailable("The microphone has no audio input. Select another microphone.")
        }
        let bridge = try AudioBridge(from: natural, to: format, continuation: continuation,
            level: { [weak self] level in
                Task { @MainActor in guard self?.token == sessionToken else { return }; self?.onLevel?(level) }
            }, failure: { [weak self] message in
                Task { @MainActor in guard self?.token == sessionToken else { return }; self?.onError?(message) }
            })
        // AVAudioEngine calls this on its audio queue. Explicit Sendable prevents
        // Swift 6 from inheriting this method's MainActor isolation.
        input.installTap(onBus: 0, bufferSize: 2048, format: natural) { @Sendable buffer, _ in bridge.consume(buffer) }
        tapInstalled = true
        inputFormat = natural
    }

    private func scheduleInputRecovery(sessionToken: UUID) {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            // Device selection can deliver several configuration notifications.
            // Coalesce them and recover outside AVAudioEngine's notification queue.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, token == sessionToken, let engine else { return }
            if !selectedMicrophoneID.isEmpty && !Self.microphones().contains(where: { $0.id == selectedMicrophoneID }) {
                onError?("The selected microphone disconnected. Select an available microphone and resume.")
                return
            }
            let current = engine.inputNode.outputFormat(forBus: 0)
            log.info("Input configuration: running=\(engine.isRunning), rate=\(current.sampleRate), channels=\(current.channelCount)")
            switch recovery.action(now: ProcessInfo.processInfo.systemUptime, isRunning: engine.isRunning, formatUnchanged: current == inputFormat) {
            case .keepRunning:
                return
            case .stop:
                onError?("The microphone keeps changing its audio configuration. Choose another input or use auto-scroll.")
            case .rebuild:
                do {
                    onStatus?("Reconnecting microphone…")
                    engine.stop()
                    if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
                    try installTap(on: engine, sessionToken: sessionToken)
                    engine.prepare()
                    try engine.start()
                    onStatus?("Listening on this Mac")
                    log.info("Microphone input recovered without resetting script position")
                } catch {
                    onError?("Could not reconnect the microphone: \(error.localizedDescription)")
                }
            }
        }
    }

    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var input = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &input, 0, nil, &inputSize) == noErr, inputSize > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &value) == noErr else { return nil }
                return value?.takeRetainedValue() as String?
            }
            guard let uid = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return Microphone(id: uid, name: name, deviceID: device)
        }
    }
}

// The audio tap invokes this bridge serially. Its converter and meter state never
// cross onto the UI actor; only immutable levels and AnalyzerInput values do.
private final class AudioBridge: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let level: @Sendable (Float) -> Void
    let failure: @Sendable (String) -> Void
    private var meterFrames: UInt32 = 0
    private var failed = false

    init(from: AVAudioFormat, to: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         level: @escaping @Sendable (Float) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw VoiceError.unavailable("Could not prepare microphone audio for recognition.") }
        self.converter = converter; self.format = to; self.continuation = continuation; self.level = level; self.failure = failure
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard !failed else { return }
        meterFrames += buffer.frameLength
        if meterFrames >= UInt32(buffer.format.sampleRate / 10), let samples = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            level(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60)))
            meterFrames = 0
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outputStatus in
            if supplied { outputStatus.pointee = .noDataNow; return nil }
            supplied = true; outputStatus.pointee = .haveData; return buffer
        }
        if status == .error {
            failed = true; failure("Could not convert microphone audio: \(error?.localizedDescription ?? "unknown error")"); return
        }
        if converted.frameLength > 0 {
            if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                failed = true; failure("Voice-follow could not keep up with audio. Pause other heavy tasks, then resume or use auto-scroll.")
            }
        }
    }
}
