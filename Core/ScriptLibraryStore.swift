import Foundation

struct ScriptLibraryStore {
    let folder: URL
    var url: URL { folder.appendingPathComponent("library.json") }

    func loadOrCreate(defaultText: String) throws -> ScriptLibrary {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            // Check version before decoding fields a newer app may have changed.
            struct Header: Decodable { let version: Int }
            guard try JSONDecoder().decode(Header.self, from: data).version == 1 else {
                throw LibraryError.unsupportedVersion
            }
            var library = try JSONDecoder().decode(ScriptLibrary.self, from: data)
            try library.validate()
            return library
        }
        var library = ScriptLibrary(defaultText: defaultText)
        if let draft = try DraftStore(url: folder.appendingPathComponent("draft.json")).load() {
            library.settings = draft.settings
            let normalized = draft.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let welcome = defaultText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !normalized.isEmpty && normalized != welcome {
                library.scripts.append(SavedScript(title: "Recovered draft", text: draft.text, position: draft.position))
            }
        }
        try library.validate()
        try save(library)
        return library
    }

    /// The caller only observes the new selection/content after the atomic write succeeds.
    func update(_ library: inout ScriptLibrary, change: (inout ScriptLibrary) -> Void) throws {
        var candidate = library
        change(&candidate)
        try candidate.validate()
        try save(candidate)
        library = candidate
    }

    private func save(_ library: ScriptLibrary) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}
