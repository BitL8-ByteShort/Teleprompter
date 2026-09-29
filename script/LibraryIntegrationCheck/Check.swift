// Runs the real AppModel and AppKit editor with isolated storage and silent speech doubles.
import AppKit
import SwiftUI

@MainActor final class SpeechService {
    var onResult: ((String, Int, Bool) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    static var starts = 0
    static var stops = 0
    static var delay: Duration = .zero
    static func microphones() -> [Microphone] { [] }
    func start(microphoneID: String, voiceEngine: VoiceEngine) async throws {
        Self.starts += 1
        try await Task.sleep(for: Self.delay)
    }
    func stop() { Self.stops += 1 }
    func releaseModel() {}
}
struct Microphone: Identifiable { let id: String; let name: String }
enum VoiceModelStore {
    static func isDownloaded(_ engine: VoiceEngine) -> Bool { engine == .apple }
    static func download(_ engine: VoiceEngine, progress: @escaping @Sendable (String) -> Void) async throws {}
}

@main struct LibraryIntegrationCheck {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel(storageFolder: folder)
        let first = model.library.activeID!
        check(model.library.scripts.count == 1, "Welcome is the only first-run script")
        check(model.text == AppModel.welcomeScript, "Default script is seeded")
        model.updateSettings { $0.countdownSeconds = 0 }
        model.edit("First script has several words to read")
        model.seek(2)
        model.togglePlayback()
        check(model.running, "Playback starts")
        model.newScript()
        let second = model.library.activeID!
        check(!model.running && model.text.isEmpty, "New script pauses playback")
        model.edit("Second script has different words for reading")
        model.seek(4)
        model.selectScript(first)
        check(model.text == "First script has several words to read" && model.playback.position == 2, "Switch flushes pending edits and restores position")
        model.togglePlayback()
        model.scrollReadingPanel(by: 8)
        check(model.running, "Manual scroll has armed resume")
        model.selectScript(second)
        try await Task.sleep(for: .milliseconds(450))
        check(!model.running && model.playback.position == 4, "Switch cancels manual-scroll resume")
        model.updateSettings { $0.mode = .voice }
        SpeechService.delay = .seconds(10)
        model.togglePlayback()
        check(model.isPreparing, "Voice startup began")
        model.selectScript(first)
        await Task.yield()
        check(!model.isPreparing && !model.running, "Switch cancels pending voice startup")
        model.importScript(text: "Imported third script", title: "Episode 3")
        let imported = model.library.activeID!
        check(model.library.scripts.count == 3, "Import creates a new script")
        check(model.library.scripts.first { $0.id == first }?.text == "First script has several words to read", "Import preserved original script")

        // Exercise the real NSTextView across selections, including the empty-library path.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ScriptEditor(model: model))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let textView = findTextView(host)!
        window.makeFirstResponder(textView)
        textView.insertText("Added ", replacementRange: NSRange(location: 0, length: 0))
        check(textView.undoManager?.canUndo == true, "Typing registers editor undo")
        model.selectScript(second)
        try await Task.sleep(for: .milliseconds(100))
        check(textView.string == model.text, "Editor displays newly selected script")
        check(textView.undoManager?.canUndo != true, "Selection clears previous script undo")
        check(textView.selectedRange().location == 0, "Selection resets editor cursor")
        window.orderOut(nil)

        model.edit("Unsaved text must stay here")
        let destination = folder.appendingPathComponent("library.json")
        let savedBytes = try Data(contentsOf: destination)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        model.selectScript(imported)
        check(model.library.activeID == second && model.text == "Unsaved text must stay here", "Failed save retains current selection and edits")
        check(model.libraryError != nil, "Failed save is reported")
        try FileManager.default.removeItem(at: destination)
        try savedBytes.write(to: destination)
        check(model.save(), "Saving recovers after destination is fixed")
        model.shutdown()
        let reopened = AppModel(storageFolder: folder)
        check(reopened.library.activeID == second && reopened.text == "Unsaved text must stay here", "Relaunch restores last script and latest edits")
        check(!reopened.running, "Relaunch is stopped")
        reopened.shutdown()
        if CommandLine.arguments.contains("--snapshot") {
            let preview = AppModel(storageFolder: folder.appendingPathComponent("preview"))
            let view = NSHostingView(rootView: ScriptWorkspaceView(model: preview))
            window.setContentSize(NSSize(width: 1230, height: 760))
            window.contentView = view
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFront(nil)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/script-library/library-preview.png"))
            }
            let sidebar = NSHostingView(rootView: ScriptLibraryView(model: preview))
            window.setContentSize(NSSize(width: 260, height: 760))
            window.contentView = sidebar
            sidebar.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            if let bitmap = sidebar.bitmapImageRepForCachingDisplay(in: sidebar.bounds) {
                sidebar.cacheDisplay(in: sidebar.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/script-library/sidebar-preview.png"))
            }
            preview.shutdown()
            window.orderOut(nil)
        }
        print("Library integration checks passed (playback, gestures, voice cancellation, import, undo, failed writes, relaunch).")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS: \(message)")
    }
    @MainActor static func findTextView(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { findTextView($0) }.first
    }
}
