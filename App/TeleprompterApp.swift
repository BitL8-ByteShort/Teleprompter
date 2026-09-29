import SwiftUI

@main
struct TeleprompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Teleprompter", id: "editor") {
            RootView(delegate: delegate)
        }
        .defaultSize(width: 1230, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script") { delegate.model.newScript() }.keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Show / Hide Prompter") { delegate.model.toggleOverlay() }
                Button("Play / Pause") { delegate.model.togglePlayback() }
                Button("Restart Script") { delegate.model.restart() }
            }
            CommandGroup(after: .help) {
                Button("Licenses & Credits") { openWindow(id: "licenses") }
            }
        }
        Window("Licenses & Credits", id: "licenses") {
            LicensesView()
        }
        .defaultSize(width: 760, height: 600)
    }
}

private struct RootView: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScriptWorkspaceView(model: delegate.model)
            .onAppear {
                delegate.openEditor = {
                    openWindow(id: "editor")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onDisappear { delegate.model.pause() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var openEditor: (() -> Void)?
    private var overlay: OverlayController?
    private var hotkeys: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(model: model)
        hotkeys = HotkeyManager(model: model)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Teleprompter")
        let menu = NSMenu()
        for (title, action) in [("Open Script Editor", #selector(showEditor)), ("Play / Pause", #selector(playPause)), ("Show / Hide Prompter", #selector(showHide)), ("Quit Teleprompter", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        statusItem = item
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)), name: NSWindow.willCloseNotification, object: nil)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationDidHide(_ notification: Notification) { model.pause() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func showEditor() { openEditor?() }
    @objc private func playPause() { model.togglePlayback() }
    @objc private func showHide() { model.toggleOverlay() }
    @objc private func suspend() { model.pause() }
    @objc private func windowClosing(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "Teleprompter" { model.pause() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
