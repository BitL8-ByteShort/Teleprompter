import Foundation

struct SpeechAlignment: Sendable {
    private var anchors: [Int: Int] = [:]
    private var finalized = Set<Int>()
    private var accepted: [Int: (words: [String], end: Int)] = [:]
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
        let transcript = Script(text).tokens.map(\.normalized)
        if let prior = accepted[segment], prior.words == transcript {
            return prior.end >= position ? prior.end : nil
        }
        // SpeechAnalyzer revises a segment in place. Anchor it once so an identical
        // partial cannot consume a second copy of a repeated phrase.
        let spoken = Array(transcript.suffix(16))
        let words = script.tokens.map(\.normalized)
        // Start on the first exact word at the selected position. This path
        // cannot skip words or search ahead, and duplicate partials were handled
        // above, so a repeated word cannot move the script again.
        if spoken.count == 1, position == anchor, words.indices.contains(position), words[position] == spoken[0] {
            accepted[segment] = (transcript, position + 1)
            return position + 1
        }
        // Use the newest exact words before comparing the whole volatile
        // transcript. Earlier errors or an ad-lib must not add several lines
        // of delay. Two words can move only at the current passage; recovery
        // farther ahead still needs at least three and stays inside 48 words.
        if spoken.count >= 2 {
            for count in stride(from: spoken.count, through: 2, by: -1) {
                let tail = Array(spoken.suffix(count))
                let first = max(0, position - (count == 2 ? 0 : 24))
                let last = min(words.count - count, position + (count == 2 ? 2 : 48 - count))
                guard first <= last else { continue }
                var nearest: (end: Int, distance: Int)?
                for start in first...last {
                    let end = start + count
                    guard end >= position, end > anchor, Array(words[start..<end]) == tail else { continue }
                    let distance = abs(start - max(anchor, position - count))
                    if nearest == nil || distance < nearest!.distance { nearest = (end, distance) }
                }
                if let nearest {
                    accepted[segment] = (transcript, nearest.end)
                    return nearest.end
                }
            }
        }
        let remaining = script.tokens.count - position
        let required = isFinal && remaining > 0 && remaining < 3 ? remaining : 3
        guard spoken.count >= required, !spoken.isEmpty else { return nil }
        // Streaming engines can keep one segment for an entire take. Bound the
        // search behind the current passage even when its original anchor is old.
        let lower = max(0, max(position - 24, min(anchor, position) - 8))
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
        // Streaming recognition often guesses the last word or two before
        // revising them. If no whole-phrase match is credible, advance through
        // its exact stable prefix without consuming those guessed words.
        if best == nil, !isFinal, spoken.count > 3 {
            for dropped in 1...min(2, spoken.count - 3) {
                let prefix = Array(spoken.dropLast(dropped))
                let last = min(words.count - prefix.count, position + 2)
                guard lower <= last else { continue }
                for start in lower...last {
                    let end = start + prefix.count
                    guard end >= position, end > anchor, Array(words[start..<end]) == prefix else { continue }
                    accepted[segment] = (transcript, end)
                    return end
                }
            }
        }
        if let best { accepted[segment] = (transcript, best.end) }
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
