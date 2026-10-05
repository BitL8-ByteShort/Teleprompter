import AudioToolbox
import AVFoundation
import CoreAudio
import Testing
@testable import TeleprompterCore

private struct PropertyWrite: Equatable {
    let property: AudioUnitPropertyID
    let scope: AudioUnitScope
    let bus: AudioUnitElement
    let value: UInt32
}

@Test func inputOnlyUnitDisablesPlaybackBeforeBindingSelectedDevice() throws {
    var writes: [PropertyWrite] = []
    try InputOnlyConfiguration.configure(device: 75) { property, scope, bus, value in
        writes.append(.init(property: property, scope: scope, bus: bus, value: value))
    }
    #expect(writes == [
        .init(property: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input, bus: 1, value: 1),
        .init(property: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output, bus: 0, value: 0),
        .init(property: kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global, bus: 0, value: 75)
    ])
}

@Test func outputDisableFailureNeverOpensTheSelectedDevice() {
    var bound = false
    enum Rejected: Error { case output }
    do {
        try InputOnlyConfiguration.configure(device: 75) { property, scope, _, _ in
            if property == kAudioOutputUnitProperty_EnableIO, scope == kAudioUnitScope_Output { throw Rejected.output }
            if property == kAudioOutputUnitProperty_CurrentDevice { bound = true }
        }
        Issue.record("Configuration should fail when output cannot be disabled")
    } catch {}
    #expect(!bound)
}

