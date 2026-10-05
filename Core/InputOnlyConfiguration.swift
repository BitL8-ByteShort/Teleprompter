import AudioToolbox
import CoreAudio

enum InputOnlyConfiguration {
    static func configure(device: AudioDeviceID,
                          write: (AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, UInt32) throws -> Void) throws {
        // AUHAL defaults to output. Disable that side before binding a device.
        // https://developer.apple.com/library/archive/technotes/tn2091/_index.html
        try write(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, 1)
        try write(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, 0)
        try write(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, device)
    }
}

