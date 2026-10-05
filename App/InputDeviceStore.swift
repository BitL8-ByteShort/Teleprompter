import CoreAudio
import Foundation

struct InputDeviceState: Equatable, Sendable {
    let uid: String
    let alive: Bool
    let sampleRate: Double
    let channels: Int
    var isUsable: Bool { alive && sampleRate > 0 && channels > 0 }
}
enum InputDeviceStore {
    static func resolve(_ microphoneID: String) throws -> AudioDeviceID {
        try resolve(microphoneID, microphones: microphones(), defaultDevice: defaultInputDevice())
    }
    static func resolve(_ microphoneID: String, microphones: [Microphone], defaultDevice: AudioDeviceID?) throws -> AudioDeviceID {
        if !microphoneID.isEmpty {
            guard let selected = microphones.first(where: { $0.id == microphoneID }) else {
                throw VoiceError.unavailable("The selected microphone isn't connected. Choose an available input.")
            }
            return selected.deviceID
        }
        guard let device = defaultDevice, microphones.contains(where: { $0.deviceID == device }) else {
            throw VoiceError.unavailable("No default microphone is available. Choose an input.")
        }
        return device
    }

    static func state(_ device: AudioDeviceID) -> InputDeviceState? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr else { return nil }
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        var rate: Float64 = 0
        size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        let deviceUID = uid.takeRetainedValue() as String
        address.mSelector = kAudioDevicePropertyStreamConfiguration
        address.mScope = kAudioObjectPropertyScopeInput
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return .init(uid: deviceUID, alive: alive != 0, sampleRate: rate,
                     channels: buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
    }
    static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return device
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
