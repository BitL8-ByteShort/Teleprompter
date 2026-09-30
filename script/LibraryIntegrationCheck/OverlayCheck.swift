import AppKit

extension LibraryIntegrationCheck {
    @MainActor static func checkOverlay() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel(storageFolder: folder)
        defer { model.shutdown() }
        let keyWindow = NSApp.keyWindow
        let overlay = OverlayController(model: model)
        defer { overlay.panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        let id = overlay.panel.windowNumber
        model.seek(5)
        let text = model.text
        let position = model.playback.position
        check(overlay.panel.isVisible && overlay.panel.contentView?.isHidden == false, "Reading panel starts visible")
        check(onScreen(id), "Cap can enumerate the reading window before recording")
        check(NSApp.keyWindow === keyWindow && !overlay.panel.canBecomeKey, "Showing the panel preserves keyboard focus")

        model.toggleOverlay()
        try await Task.sleep(for: .milliseconds(100))
        check(!model.overlayVisible && overlay.panel.contentView?.isHidden == true, "Hide conceals all panel content")
        check(overlay.panel.ignoresMouseEvents && !overlay.panel.hasShadow, "Hidden panel has no shadow and lets clicks through")
        check(overlay.panel.isVisible && onScreen(id), "Hidden panel stays in Cap's on-screen exclusion snapshot")
        check(overlay.panel.alphaValue == 1 && overlay.panel.backgroundColor == .clear && !overlay.panel.isOpaque, "Hidden panel uses a clear window without opacity tricks")
        model.updateSettings { $0.width = 480; $0.fontSize = 40 }
        check(overlay.panel.contentView?.isHidden == true && overlay.panel.ignoresMouseEvents, "Layout changes preserve hidden behavior")
        model.toggleOverlay()
        try await Task.sleep(for: .milliseconds(100))
        check(overlay.panel.windowNumber == id && onScreen(id), "Reveal reuses the excluded window ID")
        check(overlay.panel.contentView?.isHidden == false && !overlay.panel.ignoresMouseEvents && overlay.panel.hasShadow, "Reveal restores content and interaction")
        check(model.text == text && model.playback.position == position && !model.running, "Hide and reveal preserve the script, position, and pause")
        check(NSApp.keyWindow === keyWindow, "Hide and reveal preserve keyboard focus")
        print("12 reading-panel checks passed.")
    }

    @MainActor private static func onScreen(_ id: Int) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == id }
    }
}
