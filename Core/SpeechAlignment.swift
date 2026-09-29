import Foundation

struct SpeechAlignment: Sendable {
    private var anchors: [Int: Int] = [:]
    private var finalized = Set<Int>()
    mutating func reset() { anchors.removeAll(); finalized.removeAll() }

    mutating func consume(_ text: String, segment: Int, isFinal: Bool, script: Script, position: Int) -> Int? {
        guard !finalized.contains(segment) else { return nil }
        if anchors[segment] == nil { anchors[segment] = position }
        let anchor = anchors[segment] ?? position
        if isFinal { finalized.insert(segment) }
        // SpeechAnalyzer revises a segment in place. Anchor it once so an identical
        // partial cannot consume a second copy of a repeated phrase.
        let spoken = Array(Script(text).tokens.map(\.normalized).suffix(16))
        let remaining = script.tokens.count - position
        let required = isFinal && remaining > 0 && remaining < 3 ? remaining : 3
        guard spoken.count >= required, !spoken.isEmpty else { return nil }
        let words = script.tokens.map(\.normalized)
        let lower = max(0, min(anchor, position) - 8)
        let upper = min(words.count, max(anchor, position) + 48)
        guard lower < upper else { return nil }
        var best: (end: Int, score: Double)?
        for start in lower..<upper {
            for count in max(required, spoken.count - 2)...(spoken.count + 2) {
                let end = start + count
                guard end <= upper, end >= position, end > anchor else { continue }
                let candidate = Array(words[start..<end])
                let distance = Self.editDistance(spoken, candidate)
                let matched = min(spoken.count, candidate.count) - distance
                let ratio = Double(distance) / Double(max(spoken.count, candidate.count))
                guard matched >= required, ratio <= 0.28 else { continue }
                // Similarity dominates; distance from this segment's original anchor
                // breaks repeated-phrase ties in favor of the nearby passage.
                let score = ratio * 100 + Double(abs(start - anchor)) * 0.12
                if best == nil || score < best!.score { best = (end, score) }
            }
        }
        if anchors.count > 32 {
            let cutoff = anchors.keys.sorted().suffix(16)
            anchors = anchors.filter { cutoff.contains($0.key) }
            finalized = finalized.intersection(Set(cutoff))
        }
        return best?.end
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var row = Array(0...rhs.count)
        for (i, a) in lhs.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, b) in rhs.enumerated() {
                next[j + 1] = min(row[j + 1] + 1, next[j] + 1, row[j] + (a == b ? 0 : 1))
            }
            row = next
        }
        return row[rhs.count]
    }
}
