import AppKit

struct ReadingLine: Identifiable {
    let id: Int
    let text: String
    let firstWord: Int
    let endWord: Int
}

struct ReadingLayout {
    var lines: [ReadingLine] = []
    init(script: Script, fontSize: Double, width: Double) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var first = 0
        var text = ""
        for (index, token) in script.tokens.enumerated() {
            let next = text.isEmpty ? token.text : text + " " + token.text
            let paragraphBreak = index > first && script.paragraphStarts.contains(index)
            if !text.isEmpty && (paragraphBreak || (next as NSString).size(withAttributes: attributes).width > width) {
                lines.append(.init(id: lines.count, text: text, firstWord: first, endWord: index))
                first = index
                text = token.text
            } else { text = next }
        }
        if !text.isEmpty { lines.append(.init(id: lines.count, text: text, firstWord: first, endWord: script.tokens.count)) }
    }
    func offset(position: Double, lineHeight: Double, smooth: Bool) -> Double {
        guard let index = lines.lastIndex(where: { Double($0.firstWord) <= position }) else { return 0 }
        let line = lines[index]
        let fraction = smooth ? min(1, max(0, (position - Double(line.firstWord)) / Double(max(1, line.endWord - line.firstWord)))) : 0
        return (Double(index) + fraction) * lineHeight
    }
}
