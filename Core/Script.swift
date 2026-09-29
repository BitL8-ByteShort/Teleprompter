import Foundation

struct ScriptToken: Sendable {
    let text: String
    let normalized: String
    let range: NSRange
}

struct Script: Sendable {
    let text: String
    let tokens: [ScriptToken]
    let paragraphStarts: [Int]

    init(_ text: String) {
        self.text = text
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: "\\S+")
        self.tokens = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let value = source.substring(with: match.range)
            let normalized = Self.normalize(value)
            return normalized.isEmpty ? nil : ScriptToken(text: value, normalized: normalized, range: match.range)
        }
        var starts: [Int] = []
        var previousEnd = 0
        for (index, token) in tokens.enumerated() {
            let gap = source.substring(with: NSRange(location: previousEnd, length: token.range.location - previousEnd))
            if index == 0 || gap.contains("\n") { starts.append(index) }
            previousEnd = NSMaxRange(token.range)
        }
        self.paragraphStarts = starts
    }
    func paragraph(at position: Int, direction: Int) -> Int {
        if direction > 0 { return paragraphStarts.first(where: { $0 > position }) ?? tokens.count }
        return paragraphStarts.last(where: { $0 < position }) ?? 0
    }
    func word(atUTF16 offset: Int) -> Int {
        tokens.firstIndex(where: { NSMaxRange($0.range) > offset }) ?? tokens.count
    }
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
