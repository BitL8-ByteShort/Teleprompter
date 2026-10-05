import AVFoundation
import AudioToolbox
import CoreAudio

/// An input session owns only the chosen microphone, never a playback device.
protocol MicrophoneInput: AnyObject {
    var format: AVAudioFormat { get }
    func start(receive: @escaping AVAudioNodeTapBlock, failure: @escaping @Sendable (String) -> Void) throws
    func stop()
}


/// Owned serially by CaptureService or MicrophoneMonitor on MainActor. The HAL
/// callback only sees its locked context, which lives until I/O is stopped and
/// the unit is uninitialized. No device/default routes or hardware formats change.
final class InputOnlyCapture: MicrophoneInput {
    let format: AVAudioFormat
    private let unit: AudioUnit
    private let device: AudioDeviceID
    private var initialized = false
    private var context: InputRenderContext?
    private var watcher: InputDeviceWatcher?

    init(device: AudioDeviceID) throws {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw VoiceError.unavailable("Couldn't create microphone capture.")
        }
        var created: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &created), "create microphone capture")
        guard let created else { throw VoiceError.unavailable("Couldn't create microphone capture.") }
        do {
            try InputOnlyConfiguration.configure(device: device) { property, scope, bus, value in
                var value = value
                try Self.check(AudioUnitSetProperty(created, property, scope, bus, &value, UInt32(MemoryLayout<UInt32>.size)), "select microphone")
            }
            var hardware = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                               &hardware, &size), "read microphone format")
            guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardware.mSampleRate,
                      channels: hardware.mChannelsPerFrame, interleaved: false) else {
                throw VoiceError.unavailable("The selected microphone has no audio input.")
            }
            // Client-side PCM conversion at the device's existing sample rate.
            // The separate AudioBridge performs the 16 kHz resampling.
            var client = format.streamDescription.pointee
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                                &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "prepare microphone format")
            self.unit = created; self.device = device; self.format = format
        } catch {
            AudioComponentInstanceDispose(created)
            throw error
        }
    }

    func start(receive: @escaping AVAudioNodeTapBlock, failure: @escaping @Sendable (String) -> Void) throws {
        guard context == nil else { throw VoiceError.unavailable("Microphone capture is already running.") }
        var maximum: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        try Self.check(AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                           &maximum, &size), "read microphone buffer size")
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(4_096, maximum)) else {
            throw VoiceError.unavailable("Couldn't allocate microphone input.")
        }
        let context = InputRenderContext(unit: unit, buffer: buffer, receive: receive, failure: failure)
        self.context = context
        var callback = AURenderCallbackStruct(inputProc: Self.inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
        do {
            try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "prepare microphone callback")
            try Self.check(AudioUnitInitialize(unit), "initialize microphone")
            initialized = true
            watcher = try InputDeviceWatcher(device: device) { context.report($0) }
            try Self.check(AudioOutputUnitStart(unit), "start microphone")
        } catch {
            stop()
            throw error
        }
    }

    // No actor inheritance at the C audio callback boundary.
    private static let inputCallback: AURenderCallback = { opaque, flags, time, _, frames, _ in
        return Unmanaged<InputRenderContext>.fromOpaque(opaque).takeUnretainedValue().render(flags: flags, time: time, frames: frames)
    }

    func stop() {
        context?.cancel() // join any callback still converting its last audio
        watcher?.stop(); watcher = nil
        if initialized {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            initialized = false
        }
        context = nil
    }
    deinit { stop(); AudioComponentInstanceDispose(unit) }

    private static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw VoiceError.unavailable("Couldn't \(action) (\(status)).") }
    }
}

private final class InputRenderContext: @unchecked Sendable {
    private let unit: AudioUnit
    private let buffer: AVAudioPCMBuffer
    private let receive: AVAudioNodeTapBlock
    private let failure: @Sendable (String) -> Void
    private let lock = NSLock()
    private var ended = false
    private var failed = false
    init(unit: AudioUnit, buffer: AVAudioPCMBuffer, receive: @escaping AVAudioNodeTapBlock,
         failure: @escaping @Sendable (String) -> Void) {
        self.unit = unit; self.buffer = buffer; self.receive = receive; self.failure = failure
    }
    func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, time: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard !ended, !failed else { return noErr }
        guard frames <= buffer.frameCapacity else {
            failed = true; failure("The selected microphone changed its buffer size. Your reading position is held; resume.")
            return kAudioUnitErr_TooManyFramesToProcess
        }
        buffer.frameLength = frames
        let status = AudioUnitRender(unit, flags, time, 1, frames, buffer.mutableAudioBufferList)
        guard status == noErr else {
            failed = true; failure("The selected microphone stopped providing audio (\(status)). Your reading position is held.")
            return status
        }
        receive(buffer, AVAudioTime(audioTimeStamp: time, sampleRate: buffer.format.sampleRate))
        return noErr
    }
    func report(_ message: String) {
        lock.withLock {
            guard !ended, !failed else { return }
            failed = true; failure(message)
        }
    }
    func cancel() { lock.withLock { ended = true } }
}

/// Observe facts about this input only. Output/Bluetooth routing notifications
/// cannot interrupt a built-in or USB microphone that is still healthy.
private final class InputDeviceWatcher {
    private let device: AudioDeviceID
    private let queue = DispatchQueue(label: "com.bitl8byteshort.Teleprompter.input-device")
    private var registrations: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    init(device: AudioDeviceID, failure: @escaping @Sendable (String) -> Void) throws {
        self.device = device
        guard let baseline = InputDeviceStore.state(device), baseline.isUsable else {
            throw VoiceError.unavailable("The selected microphone isn't connected.")
        }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            guard InputDeviceStore.state(device) != baseline else { return }
            failure("The selected microphone disconnected or changed its input format. Your reading position is held; resume when it's ready.")
        }
        for (selector, scope) in [(kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
                                  (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
                                  (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListenerBlock(device, &address, queue, block)
            if status != noErr {
                stop()
                throw VoiceError.unavailable("Couldn't monitor the selected microphone (\(status)).")
            }
            registrations.append((address, block))
        }
    }
    func stop() {
        for (var address, block) in registrations { AudioObjectRemovePropertyListenerBlock(device, &address, queue, block) }
        registrations.removeAll()
    }
    deinit { stop() }
}
