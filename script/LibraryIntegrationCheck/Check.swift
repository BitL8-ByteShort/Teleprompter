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
        if CommandLine.arguments.contains("--overlay-only") {
            try await checkOverlay()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--mcp-fixture") {
            try await runMCPFixture(folder: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
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
        try await checkAutomation(folder: folder.appendingPathComponent("automation"))
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
        print("Library integration checks passed (playback, gestures, voice cancellation, import, undo, failed writes, relaunch, MCP).")
    }

    @MainActor static func runMCPFixture(folder: URL) async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel(storageFolder: folder)
        let original = model.library.activeID!
        model.importScript(text: "Hidden in Trash", title: "Trashed fixture")
        model.trashScript(model.library.activeID!)
        model.selectScript(original)
        model.updateSettings { $0.countdownSeconds = 0 }
        model.edit("Fixture pending edits are saved with the agent addition. " + String(repeating: "Keep reading this original take. ", count: 100))
        model.seek(2)
        model.togglePlayback()
        let server = try ScriptAutomationSocketServer(url: folder.appendingPathComponent("scripts.sock")) { model.handleAutomation($0) }
        defer { server.stop(); model.shutdown() }
        let deadline = Date().addingTimeInterval(90)
        while !FileManager.default.fileExists(atPath: folder.appendingPathComponent("stop").path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor static func checkAutomation(folder: URL) async throws {
        let model = AppModel(storageFolder: folder)
        defer { model.shutdown() }
        let original = model.library.activeID!
        model.updateSettings { $0.countdownSeconds = 0 }
        model.edit("Unsaved original words stay in the editor while another script arrives")
        model.seek(2)
        model.togglePlayback()
        let stops = SpeechService.stops
        let added = model.handleAutomation(.init(operation: .add, title: "Agent episode", text: "A new script from an agent"))
        check(added.success && model.running && model.library.activeID == original && model.playback.position == 2, "MCP add keeps the active take and position")
        check(model.text.hasPrefix("Unsaved original") && SpeechService.stops == stops, "MCP add leaves editor and speech session alone")
        let disk = try ScriptLibraryStore(folder: folder).loadOrCreate(defaultText: "unused")
        check(disk.activeScript?.text == model.text && disk.scripts.count == 2, "MCP add flushes pending edits and persists the new script together")
        model.scrollReadingPanel(by: 2)
        _ = model.handleAutomation(.init(operation: .add, title: "During gesture", text: "Still reading"))
        check(model.running, "MCP add preserves manual-scroll resume")
        let opened = model.handleAutomation(.init(operation: .open, scriptID: added.scripts[0].id))
        try await Task.sleep(for: .milliseconds(450))
        check(opened.success && !model.running && model.text == "A new script from an agent", "MCP open selects explicitly and cancels gesture resume")
        model.togglePlayback()
        check(model.handleAutomation(.init(operation: .open, scriptID: added.scripts[0].id)).success && !model.running, "MCP open pauses even the current script")
        model.updateSettings { $0.mode = .voice }
        model.togglePlayback()
        _ = model.handleAutomation(.init(operation: .add, title: "During voice startup", text: "Voice take stays armed"))
        check(model.isPreparing, "MCP add preserves pending voice startup")
        model.pause()
        model.updateSettings { $0.mode = .automatic }
        model.togglePlayback()
        let before = model.library
        check(!model.handleAutomation(.init(operation: .open, scriptID: UUID())).success && model.running, "Missing MCP script does not disturb playback")
        let destination = folder.appendingPathComponent("library.json")
        let bytes = try Data(contentsOf: destination)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        check(!model.handleAutomation(.init(operation: .add, title: "Cannot save", text: "Keep my take")).success && model.library == before && model.running, "Failed MCP add leaves library and playback unchanged")
        try FileManager.default.removeItem(at: destination)
        try bytes.write(to: destination)
        model.pause()
        for id in model.library.scripts.map(\.id) { model.trashScript(id) }
        let emptyAdd = model.handleAutomation(.init(operation: .add, title: "First again", text: "New text in an empty library"))
        check(emptyAdd.success && model.text == "New text in an empty library" && !model.running, "MCP add handles an empty library safely")
        model.save()
        let emptyDisk = try ScriptLibraryStore(folder: folder).loadOrCreate(defaultText: "unused")
        check(emptyDisk.activeScript?.text == model.text, "Empty-library MCP text survives the next autosave")
        let protectedFolder = folder.appendingPathComponent("unreadable")
        try FileManager.default.createDirectory(at: protectedFolder, withIntermediateDirectories: true)
        let protectedURL = protectedFolder.appendingPathComponent("library.json")
        try Data("broken".utf8).write(to: protectedURL)
        let protected = AppModel(storageFolder: protectedFolder)
        defer { protected.shutdown() }
        check(!protected.handleAutomation(.init(operation: .list)).success && !protected.handleAutomation(.init(operation: .add, title: "No", text: "No")).success, "MCP refuses an unreadable library")
        let protectedBytes = try Data(contentsOf: protectedURL)
        check(protectedBytes == Data("broken".utf8), "MCP keeps unreadable files untouched")
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
