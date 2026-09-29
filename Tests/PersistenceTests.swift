import Foundation
import Testing
@testable import TeleprompterCore

@Test func draftAndSettingsSurviveRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DraftStore(url: directory.appendingPathComponent("draft.json"))
    #expect(try store.load() == nil)
    var settings = PrompterSettings()
    settings.fontSize = 48
    settings.mode = .voice
    try store.save(SavedDraft(text: "My real draft", settings: settings, position: 2))
    let recovered = try #require(try store.load())
    #expect(recovered.text == "My real draft")
    #expect(recovered.settings.fontSize == 48)
    #expect(recovered.settings.mode == .voice)
    #expect(recovered.position == 2)
    // A second save replaces the entire file atomically, rather than appending.
    try store.save(SavedDraft(text: "Retake", settings: settings, position: 0))
    #expect(try store.load()?.text == "Retake")
}

@Test func corruptedDraftIsReportedInsteadOfSilentlyDiscarded() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("broken".utf8).write(to: url)
    #expect(throws: (any Error).self) { try DraftStore(url: url).load() }
}
