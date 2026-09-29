import Foundation

enum ScrollMode: String, Codable, CaseIterable, Sendable { case automatic, voice }

struct PrompterSettings: Codable, Equatable, Sendable {
    var fontSize: Double = 36
    var width: Double = 460
    var lineCount: Int = 3
    var opacity: Double = 0.94
    var wpm: Double = 130
    var mode: ScrollMode = .automatic
    var microphoneID: String = ""
    var shortcuts: [String: ShortcutBinding] = ShortcutBinding.defaults
    mutating func sanitize() {
        fontSize = fontSize.isFinite ? min(64, max(24, fontSize)) : 36
        width = width.isFinite ? min(720, max(320, width)) : 460
        lineCount = min(4, max(2, lineCount))
        opacity = opacity.isFinite ? min(1, max(0.35, opacity)) : 0.94
        wpm = wpm.isFinite ? min(240, max(60, wpm)) : 130
    }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let defaults: [String: ShortcutBinding] = [
        "play": .init(keyCode: 35, modifiers: 2304, label: "⌥⌘P"),
        "previous": .init(keyCode: 123, modifiers: 2304, label: "⌥⌘←"),
        "next": .init(keyCode: 124, modifiers: 2304, label: "⌥⌘→"),
        "restart": .init(keyCode: 15, modifiers: 2304, label: "⌥⌘R"),
        "overlay": .init(keyCode: 4, modifiers: 2304, label: "⌥⌘H")
    ]
}

struct SavedDraft: Codable, Sendable {
    var text: String
    var settings: PrompterSettings
    var position: Double
}

struct DraftStore {
    let url: URL
    func save(_ draft: SavedDraft) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(draft).write(to: url, options: .atomic)
    }
    func load() throws -> SavedDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var draft = try JSONDecoder().decode(SavedDraft.self, from: Data(contentsOf: url))
        draft.settings.sanitize()
        draft.position = draft.position.isFinite ? max(0, draft.position) : 0
        return draft
    }
}
