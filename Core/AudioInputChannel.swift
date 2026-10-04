import Foundation
import Synchronization

/// Single-consumer microphone channel. Its budget is audio time, independent of
/// the input device's callback size. The tap never waits for model inference.
public final class AudioInputChannel<Element: Sendable>: Sendable {
    public enum Delivery: Sendable { case accepted, overflow, closed }
    private struct State {
        var pending: [(value: Element, frames: Int)] = []
        var frames = 0
        var closed = false
    }
    private let state = Mutex(State())
    private let frameLimit: Int
    private let signals: AsyncStream<Void>
    private let wake: AsyncStream<Void>.Continuation

    public init(sampleRate: Double, seconds: Double = 4) {
        frameLimit = max(1, Int(sampleRate * seconds))
        (signals, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public var stream: AsyncStream<Element> {
        AsyncStream(unfolding: { [self] in await next() })
    }
    public var queuedFrames: Int { state.withLock { $0.frames } }

    public func offer(_ value: Element, frames: Int) -> Delivery {
        let result: Delivery = state.withLock { state in
            guard !state.closed else { return .closed }
            // Also bound object overhead if a device sends unusually tiny buffers.
            guard frames > 0 else { return .accepted }
            guard frames <= frameLimit - state.frames, state.pending.count < 1_024 else {
                // Never splice speech on either side of an audio gap. The caller
                // starts a fresh recognition session; stale audio is discarded.
                state.closed = true
                state.pending.removeAll()
                state.frames = 0
                return .overflow
            }
            state.pending.append((value, frames))
            state.frames += frames
            return .accepted
        }
        switch result {
        case .accepted: wake.yield(())
        case .overflow: wake.finish()
        case .closed: break
        }
        return result
    }

    private func next() async -> Element? {
        var iterator = signals.makeAsyncIterator()
        while true {
            let item = state.withLock { state -> Element? in
                guard !state.pending.isEmpty else { return nil }
                let first = state.pending.removeFirst()
                state.frames -= first.frames
                return first.value
            }
            if let item { return item }
            if state.withLock({ $0.closed }) { return nil }
            guard await iterator.next() != nil else { return nil }
        }
    }

    public func finish(drain: Bool = false) {
        state.withLock { state in
            state.closed = true
            if !drain {
                state.pending.removeAll()
                state.frames = 0
            }
        }
        wake.finish()
    }
}
