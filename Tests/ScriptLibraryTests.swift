import Foundation
import Testing
@testable import TeleprompterCore

struct ScriptLibraryTests {
    private func withStore(_ body: (ScriptLibraryStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(ScriptLibraryStore(folder: folder))
    }

    @Test func welcomeIsSavedOnceAndLegacyDraftIsPreserved() throws {
        try withStore { store in
            let draft = DraftStore(url: store.folder.appendingPathComponent("draft.json"))
            var settings = PrompterSettings()
            settings.wpm = 155
            try draft.save(.init(text: "A previous personal script", settings: settings, position: 2.5))
            let original = try Data(contentsOf: draft.url)
            let library = try store.loadOrCreate(defaultText: "Welcome to Teleprompter.")
            #expect(library.activeScript?.title == "Welcome to Teleprompter")
            #expect(library.activeScript?.position == 0)
            #expect(library.scripts.count == 2)
            #expect(library.scripts.last?.text == "A previous personal script")
            #expect(library.scripts.last?.position == 2.5)
            #expect(library.settings.wpm == 155)
            #expect(try Data(contentsOf: draft.url) == original)
            #expect(try store.loadOrCreate(defaultText: "New default") == library)
        }
    }

    @Test func whitespaceOnlyDifferencesDoNotDuplicateDefault() throws {
        try withStore { store in
            try DraftStore(url: store.folder.appendingPathComponent("draft.json"))
                .save(.init(text: " Welcome\n\n to Teleprompter. ", settings: .init(), position: 2))
            let library = try store.loadOrCreate(defaultText: "Welcome to Teleprompter.")
            #expect(library.scripts.count == 1)
            #expect(library.activeScript?.position == 0)
        }
    }

    @Test func independentTextPositionsSettingsAndSelectionSurviveRelaunch() throws {
        try withStore { store in
            var library = try store.loadOrCreate(defaultText: "First second third fourth fifth")
            let first = try #require(library.activeID)
            try store.update(&library) { value in
                value.updateActive(text: "Edited first script with more words", position: 2.75)
                value.settings.fontSize = 48
                value.create(title: "Episode 2", text: "A different script for another episode")
                value.updateActive(text: "A different script for another episode", position: 4.25)
            }
            let second = try #require(library.activeID)
            #expect(first != second)
            var restored = try store.loadOrCreate(defaultText: "unused")
            #expect(restored == library)
            #expect(restored.activeScript?.position == 4.25)
            restored.select(first)
            #expect(restored.activeScript?.text == "Edited first script with more words")
            #expect(restored.activeScript?.position == 2.75)
            #expect(restored.settings.fontSize == 48)
        }
    }

    @Test func renameDuplicateAndSearchKeepIndependentScripts() throws {
        var library = ScriptLibrary(defaultText: "My café script")
        let first = try #require(library.activeID)
        library.rename(first, title: "  Episode 1  ")
        library.updateActive(text: "My café script", position: 2)
        library.duplicate(first)
        let copy = try #require(library.activeScript)
        #expect(copy.id != first)
        #expect(copy.title == "Episode 1 copy")
        #expect(copy.position == 0)
        #expect(copy.text == "My café script")
        library.updateActive(text: "Edited copy", position: 1)
        #expect(library.matching(query: "CAFE").map(\.id) == [first])
        #expect(library.matching(query: "episode").count == 2)
        #expect(library.matching(query: " ").count == 2)
        library.rename(copy.id, title: " \n ")
        #expect(library.activeScript?.title == "Untitled script")
    }

    @Test func trashAndRestoreLastScriptRetainTextAndPosition() throws {
        try withStore { store in
            var library = try store.loadOrCreate(defaultText: "One two three four")
            let id = try #require(library.activeID)
            try store.update(&library) { value in
                value.updateActive(text: "One two three four", position: 2.5)
                value.trash(id)
            }
            #expect(library.activeID == nil)
            #expect(library.matching(query: "").isEmpty)
            #expect(library.matching(query: "", trashed: true).count == 1)
            var reopened = try store.loadOrCreate(defaultText: "Do not reseed")
            #expect(reopened.activeID == nil)
            #expect(reopened.scripts.count == 1)
            try store.update(&reopened) { $0.restore(id) }
            #expect(reopened.activeID == id)
            #expect(reopened.activeScript?.position == 2.5)
            #expect(reopened.activeScript?.text == "One two three four")
        }
    }

    @Test func deletingNonSelectedScriptDoesNotChangeSelection() throws {
        var library = ScriptLibrary(defaultText: "Welcome")
        let first = try #require(library.activeID)
        library.create(title: "New", text: "Text")
        let second = library.activeID
        library.trash(first)
        #expect(library.activeID == second)
        library.select(first) // Trashed scripts cannot become the editor selection.
        #expect(library.activeID == second)
        library.restore(first)
        #expect(library.activeID == second)
        library.trash(try #require(second))
        #expect(library.activeID == first)
    }

    @Test func failedWriteDoesNotCommitNavigationOrEdits() throws {
        try withStore { store in
            var library = try store.loadOrCreate(defaultText: "Keep my text")
            let before = library
            // A directory at the destination makes atomic replacement fail even as root.
            try FileManager.default.removeItem(at: store.url)
            try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) {
                try store.update(&library) { $0.create(title: "Should not open", text: "Other") }
            }
            #expect(library == before)
        }
    }

    @Test func corruptedAndFutureLibrariesRemainUntouched() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
            for raw in ["broken", "{\"version\":999}"] {
                let bytes = Data(raw.utf8)
                try bytes.write(to: store.url)
                #expect(throws: (any Error).self) { try store.loadOrCreate(defaultText: "Welcome") }
                #expect(try Data(contentsOf: store.url) == bytes)
            }
        }
    }

    @Test func normalizationClampsPositionsAndRepairsMissingSelection() throws {
        var library = ScriptLibrary(defaultText: "One two three")
        library.updateActive(text: "One two three", position: 100)
        #expect(library.activeScript?.position == 3)
        library.updateActive(text: "One two three", position: .nan)
        #expect(library.activeScript?.position == 0)
        library.activeID = UUID()
        try library.validate()
        #expect(library.activeID == library.scripts.first?.id)
    }
}
