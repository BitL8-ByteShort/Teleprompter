import AVFoundation
import Synchronization
import Testing
@testable import TeleprompterCore

@Test func briefStallBudgetIsAudioTimeRatherThanCallbackCount() async {
    let channel = AudioInputChannel<Int>(sampleRate: 16_000)
    // 100 small callbacks are only one second, well inside the four-second budget.
    for n in 0..<100 { #expect(channel.offer(n, frames: 160) == .accepted) }
    channel.finish(drain: true)
    var iterator = channel.stream.makeAsyncIterator()
    for n in 0..<100 { #expect(await iterator.next() == n) }
    #expect(await iterator.next() == nil)
}

@Test func prolongedStallClosesOldAudioOnceInsteadOfSplicingAcrossAGap() async {
    let channel = AudioInputChannel<Int>(sampleRate: 16_000, seconds: 0.2)
    #expect(channel.offer(1, frames: 1_600) == .accepted)
    #expect(channel.offer(2, frames: 1_600) == .accepted)
    #expect(channel.offer(3, frames: 1_600) == .overflow)
    #expect(channel.offer(4, frames: 1_600) == .closed)
    var iterator = channel.stream.makeAsyncIterator()
    #expect(await iterator.next() == nil)
}

@Test func consumptionFreesAudioBudgetAndPauseDiscardsPendingAudio() async {
    let channel = AudioInputChannel<Int>(sampleRate: 48_000, seconds: 0.1)
    var iterator = channel.stream.makeAsyncIterator()
    for n in 0..<200 {
        #expect(channel.offer(n, frames: 4_800) == .accepted)
        #expect(await iterator.next() == n)
    }
    #expect(channel.offer(200, frames: 4_800) == .accepted)
    channel.finish()
    #expect(channel.offer(201, frames: 1) == .closed)
    #expect(await iterator.next() == nil)
}

@Test func finishWakesAnIdleConsumer() async {
    let channel = AudioInputChannel<Int>(sampleRate: 16_000)
    let reader = Task { var iterator = channel.stream.makeAsyncIterator(); return await iterator.next() }
    channel.finish()
    #expect(await reader.value == nil)
}

@Test func realConverterTreatsBacklogAsOneRecoveryAndAFreshTapContinues() async throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let events = Mutex((recoveries: 0, failures: 0))
    let channel = AudioInputChannel<[Float]>(sampleRate: 16_000, seconds: 0.2)
    let bridge = try AudioBridge(from: format, to: format, deliver: { buffer in
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let result = channel.offer(samples, frames: samples.count)
        if result == .overflow { events.withLock { $0.recoveries += 1 } }
        return result == .accepted
    }, level: { _ in }, failure: { _ in events.withLock { $0.failures += 1 } })
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
    buffer.frameLength = 1_600
    buffer.floatChannelData![0].initialize(repeating: 0.1, count: 1_600)
    for _ in 0..<100 { bridge.consume(buffer) }
    #expect(events.withLock { $0.recoveries } == 1)
    #expect(events.withLock { $0.failures } == 0)
    #expect(channel.queuedFrames == 0)

    // A warmed recognizer uses a new channel/tap, never the gapped old stream.
    let fresh = AudioInputChannel<[Float]>(sampleRate: 16_000, seconds: 0.2)
    let resumed = try AudioBridge(from: format, to: format, deliver: { buffer in
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        return fresh.offer(samples, frames: samples.count) == .accepted
    }, level: { _ in }, failure: { _ in events.withLock { $0.failures += 1 } })
    var iterator = fresh.stream.makeAsyncIterator()
    for _ in 0..<100 {
        resumed.consume(buffer)
        #expect(await iterator.next()?.count == 1_600)
    }
    fresh.finish()
    #expect(events.withLock { $0.failures } == 0)
}
