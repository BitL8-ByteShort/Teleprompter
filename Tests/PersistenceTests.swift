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

@Test func addingAlignmentPreservesDraftsSavedByEarlierVersions() throws {
    let oldDraft = Data(#"{"text":"Keep my script","position":7,"settings":{"fontSize":32,"width":440,"lineCount":4,"opacity":0.6,"wpm":145,"mode":"voice","microphoneID":"BuiltInMicrophoneDevice","shortcuts":{"play":{"keyCode":35,"modifiers":2304,"label":"⌥⌘P"}}}}"#.utf8)
    let recovered = try JSONDecoder().decode(SavedDraft.self, from: oldDraft)
    #expect(recovered.text == "Keep my script")
    #expect(recovered.position == 7)
    #expect(recovered.settings.alignment == .left)
    #expect(recovered.settings.fontSize == 32)
    #expect(recovered.settings.width == 440)
    #expect(recovered.settings.lineCount == 4)
    #expect(recovered.settings.opacity == 0.6)
    #expect(recovered.settings.wpm == 145)
    #expect(recovered.settings.mode == .voice)
    #expect(recovered.settings.microphoneID == "BuiltInMicrophoneDevice")
    #expect(recovered.settings.shortcuts["play"]?.label == "⌥⌘P")
}

@Test func readingAlignmentSurvivesSavingAndReloading() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("draft.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DraftStore(url: url)
    for alignment in ReadingAlignment.allCases {
        var settings = PrompterSettings()
        settings.alignment = alignment
        try store.save(.init(text: "My script", settings: settings, position: 3))
        let recovered = try #require(try store.load())
        #expect(recovered.settings.alignment == alignment)
        #expect(recovered.text == "My script")
        #expect(recovered.position == 3)
    }
}
