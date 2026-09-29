import Foundation

struct SpeechAlignment: Sendable {
    private var anchors: [Int: Int] = [:]
    private var finalized = Set<Int>()
    private var accepted: [Int: (text: String, end: Int)] = [:]
    mutating func reset() { anchors.removeAll(); finalized.removeAll(); accepted.removeAll() }

    mutating func consume(_ text: String, segment: Int, isFinal: Bool, script: Script, position: Int) -> Int? {
        guard !finalized.contains(segment) else { return nil }
        if anchors[segment] == nil { anchors[segment] = position }
        let anchor = anchors[segment] ?? position
        if isFinal { finalized.insert(segment) }
        defer {
            if anchors.count > 32 {
                let keep = Set(anchors.keys.sorted().suffix(16))
                anchors = anchors.filter { keep.contains($0.key) }
                accepted = accepted.filter { keep.contains($0.key) }
                finalized = finalized.intersection(keep)
            }
        }
        if let prior = accepted[segment], prior.text == text {
            return prior.end >= position ? prior.end : nil
        }
        // SpeechAnalyzer revises a segment in place. Anchor it once so an identical
        // partial cannot consume a second copy of a repeated phrase.
        let spoken = Array(Script(text).tokens.map(\.normalized).suffix(16))
        let words = script.tokens.map(\.normalized)
        // Two exact words at the current passage are enough to start moving.
        // This narrow path does not permit fuzzy or distant two-word matches.
        if spoken.count == 2, words.count >= 2, anchor <= words.count - 2 {
            for start in max(0, anchor)...min(words.count - 2, anchor + 2) {
                let end = start + 2
                if end >= position, Array(words[start..<end]) == spoken {
                    accepted[segment] = (text, end)
                    return end
                }
            }
        }
        let remaining = script.tokens.count - position
        let required = isFinal && remaining > 0 && remaining < 3 ? remaining : 3
        guard spoken.count >= required, !spoken.isEmpty else { return nil }
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
        // An ad-lib can remain in a volatile transcript after the reader resumes.
        // Recover from an exact recent suffix close to the current word, instead
        // of waiting for the whole transcript to become mostly script again.
        if best == nil, spoken.count > 3 {
            for count in stride(from: min(8, spoken.count - 1), through: 3, by: -1) {
                let tail = Array(spoken.suffix(count))
                let first = max(0, position - 8)
                let last = min(words.count - count, position + 3)
                guard first <= last else { continue }
                for start in first...last {
                    let end = start + count
                    guard end >= position, end > anchor, Array(words[start..<end]) == tail else { continue }
                    let score = Double(abs(start - anchor))
                    if best == nil || score < best!.score { best = (end, score) }
                }
                if best != nil { break }
            }
        }
        if let best { accepted[segment] = (text, best.end) }
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
