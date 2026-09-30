import Foundation

struct SavedScript: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var text: String
    var position: Double = 0
    var createdAt = Date()
    var modifiedAt = Date()
    var trashedAt: Date?

    var preview: String {
        let snippet = text.prefix(240).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return snippet.isEmpty ? "Empty script" : snippet
    }
}

struct ScriptLibrary: Codable, Equatable, Sendable {
    var version = 1
    var scripts: [SavedScript]
    var activeID: UUID?
    var settings = PrompterSettings()

    init(defaultText: String) {
        let welcome = SavedScript(title: "Welcome to Teleprompter", text: defaultText)
        scripts = [welcome]
        activeID = welcome.id
    }

    var activeScript: SavedScript? {
        scripts.first { $0.id == activeID && $0.trashedAt == nil }
    }

    func matching(query: String, trashed: Bool = false) -> [SavedScript] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return scripts.filter {
            ($0.trashedAt != nil) == trashed && (query.isEmpty ||
                $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query))
        }.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    @discardableResult mutating func create(title: String = "Untitled script", text: String = "", select: Bool = true) -> UUID {
        let item = SavedScript(title: uniqueTitle(Self.cleanTitle(title)), text: text)
        scripts.append(item)
        if select { activeID = item.id }
        return item.id
    }

    mutating func select(_ id: UUID) {
        guard scripts.contains(where: { $0.id == id && $0.trashedAt == nil }) else { return }
        activeID = id
    }

    mutating func updateActive(text: String, position: Double) {
        guard let index = scripts.firstIndex(where: { $0.id == activeID && $0.trashedAt == nil }) else { return }
        if scripts[index].text != text {
            scripts[index].text = text
            scripts[index].modifiedAt = Date()
        }
        scripts[index].position = Self.clampedPosition(position, text: text)
    }

    mutating func rename(_ id: UUID, title: String) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        let title = Self.cleanTitle(title)
        guard scripts[index].title != title else { return }
        scripts[index].title = title
        scripts[index].modifiedAt = Date()
    }

    mutating func duplicate(_ id: UUID) {
        guard let source = scripts.first(where: { $0.id == id && $0.trashedAt == nil }) else { return }
        create(title: source.title + " copy", text: source.text)
    }

    mutating func trash(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id && $0.trashedAt == nil }) else { return }
        scripts[index].trashedAt = Date()
        if activeID == id { activeID = matching(query: "").first?.id }
    }

    mutating func restore(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id && $0.trashedAt != nil }) else { return }
        scripts[index].trashedAt = nil
        if activeScript == nil { activeID = id }
    }

    mutating func validate() throws {
        guard version == 1 else { throw LibraryError.unsupportedVersion }
        guard Set(scripts.map(\.id)).count == scripts.count else { throw LibraryError.duplicateIdentifiers }
        settings.sanitize()
        for index in scripts.indices {
            scripts[index].title = Self.cleanTitle(scripts[index].title)
            scripts[index].position = Self.clampedPosition(scripts[index].position, text: scripts[index].text)
        }
        if activeScript == nil { activeID = matching(query: "").first?.id }
    }

    private static func clampedPosition(_ position: Double, text: String) -> Double {
        guard position.isFinite else { return 0 }
        return min(Double(text.split(whereSeparator: \.isWhitespace).count), max(0, position))
    }

    private static func cleanTitle(_ title: String) -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Untitled script" : value
    }

    private func uniqueTitle(_ title: String) -> String {
        let names = Set(scripts.filter { $0.trashedAt == nil }.map(\.title))
        var candidate = title
        var suffix = 2
        while names.contains(candidate) { candidate = "\(title) \(suffix)"; suffix += 1 }
        return candidate
    }
}

enum LibraryError: LocalizedError {
    case unsupportedVersion, duplicateIdentifiers
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This library was saved by a newer version of Teleprompter. Update the app to open it."
        case .duplicateIdentifiers: "This library contains duplicate script identifiers. Its original file has been kept."
        }
    }
}
