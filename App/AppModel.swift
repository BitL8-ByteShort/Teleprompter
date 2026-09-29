import AppKit
import Observation
import OSLog

@MainActor @Observable
final class AppModel {
    var text: String
    var settings: PrompterSettings
    var script: Script
    var layout: ReadingLayout
    var playback = Playback()
    private var manualScroll = ManualScrollSession()
    var readingOffset: Double = 0
    var selection = NSRange(location: 0, length: 0)
    var overlayVisible = true
    var errorMessage: String?
    var speechStatus = "Ready when you are"
    var microphoneLevel: Float = 0
    var isPreparing = false
    var shortcutError: String?
    var recordingShortcut: String?
    var saveStatus = "Saved on this Mac"
    var microphones: [Microphone] = []
    var downloadedEngines: Set<VoiceEngine> = [.apple]
    var downloadingEngine: VoiceEngine?
    var downloadStatus = ""
    var modelDownloadError: String?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored var overlayChanged: (() -> Void)?
    @ObservationIgnored var shortcutsChanged: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var alignment = SpeechAlignment()
    @ObservationIgnored private var voiceScroll = VoiceScroll()
    @ObservationIgnored private let speech = SpeechService()
    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private var lastSave: Double = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var protectUnreadableDraft = false
    @ObservationIgnored private let log = Logger(subsystem: "com.bitl8byteshort.Teleprompter", category: "Playback")

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Teleprompter")
        store = DraftStore(url: folder.appendingPathComponent("draft.json"))
        var restored: SavedDraft?
        var recoveryError: String?
        var protectDraft = false
        do { restored = try store.load() }
        catch {
            // Preserve an unreadable draft before future autosaves replace it.
            let backup = folder.appendingPathComponent("draft-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do { try FileManager.default.copyItem(at: store.url, to: backup) }
            catch {
                protectDraft = true
                recoveryError = "Your saved draft could not be read or backed up. Export any edits before quitting, and check \(folder.path)."
            }
            if recoveryError == nil { recoveryError = "Your saved draft could not be read. A copy was kept at \(backup.path)." }
        }
        let initialText = restored?.text ?? Self.welcomeScript
        let initialSettings = restored?.settings ?? PrompterSettings()
        let initialScript = Script(initialText)
        text = initialText
        settings = initialSettings
        script = initialScript
        layout = ReadingLayout(script: initialScript, fontSize: initialSettings.fontSize, width: initialSettings.width - 48)
        playback.position = min(Double(script.tokens.count), restored?.position ?? 0)
        if playback.position >= Double(script.tokens.count) { playback.position = 0 }
        errorMessage = recoveryError
        protectUnreadableDraft = protectDraft
        syncReadingOffset()
        speech.onResult = { [weak self] text, segment, final in self?.receive(text, segment: segment, final: final) }
        speech.onLevel = { [weak self] level in self?.microphoneLevel = level }
        speech.onStatus = { [weak self] status in self?.speechStatus = status }
        speech.onError = { [weak self] message in self?.speechFailed(message) }
        refreshMicrophones()
        refreshModels()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var running: Bool { playback.state == .playing || playback.state == .countdown || isPreparing || manualScroll.shouldResume }
    var lineHeight: Double { settings.fontSize * 1.35 }
    var progress: Double { script.tokens.isEmpty ? 0 : min(1, playback.position / Double(script.tokens.count)) }
    var estimatedMinutes: Int { Int(ceil(Double(script.tokens.count) / settings.wpm)) }
    var stateLabel: String {
        if manualScroll.shouldResume { return "Repositioning…" }
        if isPreparing { return "Preparing voice-follow…" }
        switch playback.state {
        case .stopped: return "Ready"
        case .countdown: return "Starting in \(Int(ceil(playback.countdown)))"
        case .playing: return settings.mode == .voice ? "Following your voice" : "Reading"
        case .paused: return "Paused"
        case .finished: return "Take complete"
        }
    }

    func edit(_ value: String) {
        guard value != text else { return }
        pause()
        let oldOffset = script.tokens.indices.contains(Int(playback.position)) ? script.tokens[Int(playback.position)].range.location : 0
        text = value
        script = Script(value)
        playback.seek(Double(script.word(atUTF16: oldOffset)), wordCount: script.tokens.count)
        rebuildLayout()
        alignment.reset()
        scheduleSave()
    }

    func updateSettings(_ change: (inout PrompterSettings) -> Void) {
        let old = settings
        change(&settings)
        settings.sanitize()
        if old.mode != settings.mode || old.microphoneID != settings.microphoneID || old.voiceEngine != settings.voiceEngine { pause() }
        if old.mode != settings.mode || old.voiceEngine != settings.voiceEngine { speech.releaseModel() }
        if old.fontSize != settings.fontSize || old.width != settings.width { rebuildLayout() }
        if old.mode != settings.mode { syncReadingOffset() }
        if old.shortcuts != settings.shortcuts { shortcutsChanged?() }
        overlayChanged?()
        scheduleSave()
    }

    func rebuildLayout() {
        layout = ReadingLayout(script: script, fontSize: settings.fontSize, width: settings.width - 48)
        syncReadingOffset()
    }

    private func syncReadingOffset() {
        readingOffset = layout.offset(position: playback.position, lineHeight: lineHeight)
        voiceScroll.reset(to: readingOffset)
    }

    func togglePlayback() {
        if running { pause(); return }
        startPlayback(delay: Double(settings.countdownSeconds))
    }

    private func startPlayback(delay: Double) {
        manualScroll.cancel()
        guard !script.tokens.isEmpty else { return }
        if !overlayVisible { overlayVisible = true; overlayChanged?() }
        errorMessage = nil
        alignment.reset()
        if settings.mode == .automatic {
            playback.play(now: ProcessInfo.processInfo.systemUptime, wordCount: script.tokens.count, delay: delay)
            syncReadingOffset()
            log.info("Started automatic playback")
            return
        }
        isPreparing = true
        generation += 1
        let token = generation
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await speech.start(microphoneID: settings.microphoneID, voiceEngine: settings.voiceEngine)
                guard !Task.isCancelled, generation == token else { return }
                isPreparing = false
                playback.play(now: ProcessInfo.processInfo.systemUptime, wordCount: script.tokens.count, delay: delay)
                syncReadingOffset()
                log.info("Started voice playback")
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                speechFailed(error.localizedDescription)
            }
        }
    }

    func pause() {
        manualScroll.cancel()
        generation += 1
        startTask?.cancel(); startTask = nil
        isPreparing = false
        playback.pause()
        speech.stop()
        microphoneLevel = 0
        speechStatus = "Microphone off"
        save()
    }

    func seek(_ word: Int) {
        pause()
        playback.seek(Double(word), wordCount: script.tokens.count)
        syncReadingOffset()
        alignment.reset()
        save()
    }
    func scrollReadingPanel(by delta: Double) {
        guard delta.isFinite, delta != 0, !layout.lines.isEmpty else { return }
        // Pause capture once and remember whether this gesture interrupted a take.
        // Later momentum events extend the hold without changing that intent.
        let wasRunning = running
        if !manualScroll.isActive { pause() }
        manualScroll.record(now: ProcessInfo.processInfo.systemUptime, wasRunning: wasRunning)
        // Start from the visible offset, which can trail recognized speech.
        let position = layout.scrolledPosition(from: readingOffset, by: delta, lineHeight: lineHeight)
        playback.seek(position, wordCount: script.tokens.count)
        syncReadingOffset()
        alignment.reset()
        scheduleSave()
    }
    func paragraph(_ direction: Int) { seek(script.paragraph(at: Int(playback.position), direction: direction)) }
    func restart() { seek(0) }
    func resume(from word: Int) { seek(word); togglePlayback() }
    func readFromSelection() { resume(from: script.word(atUTF16: selection.location)) }
    func toggleOverlay() {
        overlayVisible.toggle()
        if !overlayVisible { pause() }
        overlayChanged?()
    }
    func refreshMicrophones() { microphones = SpeechService.microphones() }
    func refreshModels() {
        downloadedEngines = Set(VoiceEngine.allCases.filter { VoiceModelStore.isDownloaded($0) })
    }
    func selectEngine(_ engine: VoiceEngine) {
        refreshModels()
        guard downloadedEngines.contains(engine) else { return }
        updateSettings { $0.voiceEngine = engine }
        errorMessage = nil
        speechStatus = "\(engine.title) selected · microphone off"
    }
    func downloadModel(_ engine: VoiceEngine) {
        guard downloadingEngine == nil, engine != .apple else { return }
        downloadingEngine = engine
        downloadStatus = "Starting download…"
        modelDownloadError = nil
        downloadTask = Task { [weak self] in
            do {
                try await VoiceModelStore.download(engine) { [weak self] status in
                    Task { @MainActor in
                        guard self?.downloadingEngine == engine else { return }
                        self?.downloadStatus = status
                    }
                }
                try Task.checkCancellation()
                self?.refreshModels()
            } catch {
                if !Task.isCancelled { self?.modelDownloadError = "\(engine.title): \(error.localizedDescription)" }
            }
            self?.downloadingEngine = nil
            self?.downloadTask = nil
        }
    }
    func cancelModelDownload() {
        downloadTask?.cancel()
        downloadStatus = "Cancelling…"
    }
    func useAutoScroll() { pause(); speech.releaseModel(); settings.mode = .automatic; errorMessage = nil; scheduleSave() }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if manualScroll.isActive, manualScroll.takeResumeIfSettled(now: now) {
            startPlayback(delay: 0)
        }
        guard playback.state == .playing || playback.state == .countdown else { return }
        let previous = playback.state
        let elapsed = max(0, now - (playback.lastTime ?? now))
        let scrollSettled = abs(readingOffset - layout.offset(position: playback.position, lineHeight: lineHeight)) < 0.5
        playback.tick(now: now, wordCount: script.tokens.count, wpm: settings.wpm, automatic: settings.mode == .automatic,
                      readyToFinish: settings.mode == .automatic || scrollSettled)
        let target = layout.offset(position: playback.position, lineHeight: lineHeight)
        if settings.mode == .voice {
            readingOffset = voiceScroll.advance(to: target, elapsed: elapsed, lineHeight: lineHeight)
        } else { readingOffset = target }
        if playback.state == .finished && previous != .finished {
            speech.stop(); microphoneLevel = 0; speechStatus = "Microphone off"; save()
        }
        if running && now - lastSave > 5 { save(); lastSave = now }
    }
    private func receive(_ recognized: String, segment: Int, final: Bool) {
        guard settings.mode == .voice, playback.state == .playing else { return }
        if let word = alignment.consume(recognized, segment: segment, isFinal: final, script: script, position: Int(playback.position)) {
            playback.position = Double(max(Int(playback.position), word))
            speechStatus = "Following your script"
            log.info("Speech aligned at word \(word)")
        } else { speechStatus = "Listening · holding your place" }
    }
    private func speechFailed(_ message: String) {
        pause()
        errorMessage = message
        speechStatus = "Voice-follow unavailable"
        log.error("Voice-follow failed: \(message, privacy: .public)")
    }
    private func scheduleSave() {
        saveStatus = "Saving…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.save()
        }
    }
    func save() {
        guard !protectUnreadableDraft else { saveStatus = "Autosave paused to protect unreadable draft. Export your edits."; return }
        do {
            try store.save(.init(text: text, settings: settings, position: playback.position))
            saveStatus = "Saved on this Mac"
        } catch { saveStatus = "Could not save: \(error.localizedDescription)" }
    }
    func shutdown() { downloadTask?.cancel(); pause(); speech.releaseModel(); saveTask?.cancel(); save(); timer?.invalidate() }

    static let welcomeScript = """
    Welcome to Teleprompter.

    Keep your eyes near the camera, take a breath, and speak at your own pace.

    Paste your YouTube script here. Choose auto-scroll for a steady rhythm, or voice-follow to let the words move with you.

    A pause is fine. A retake is fine. Your next thought will be right here.
    """
}
