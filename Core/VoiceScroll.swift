import Foundation

struct VoiceScroll {
    private(set) var offset = 0.0
    private var velocity = 0.0
    mutating func reset(to offset: Double) { self.offset = offset; velocity = 0 }
    mutating func advance(to target: Double, elapsed: Double, lineHeight: Double) -> Double {
        // Recognized words arrive in bursts. Retain velocity across those updates
        // and approach their fractional-line position without overshoot or drift.
        let dt = min(1.0 / 30, max(0, elapsed))
        guard dt > 0 else { return offset }
        let target = max(offset, target)
        let omega = 2.0 / 0.32
        let gap = offset - target
        let change = velocity + omega * gap
        let decay = exp(-omega * dt)
        let proposed = target + (gap + change * dt) * decay
        let maxSpeed = max(1, lineHeight) * 2.5
        let next = min(target, offset + maxSpeed * dt, max(offset, proposed))
        velocity = min(maxSpeed, max(0, (velocity - omega * change * dt) * decay))
        if next == target { velocity = 0 }
        offset = next
        return offset
    }
}
