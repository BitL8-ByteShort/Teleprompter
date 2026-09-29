import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    private let model: AppModel
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var monitor: Any?
    private let actions = ["play", "previous", "next", "restart", "overlay"]

    init(model: AppModel) {
        self.model = model
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.perform(Int(identifier.id)) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.capture(event) == nil }
            return consumed ? nil : event
        }
        model.shortcutsChanged = { [weak self] in self?.register() }
        register()
    }

    func register() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
        model.shortcutError = nil
        for (index, action) in actions.enumerated() {
            guard let binding = model.settings.shortcuts[action] else { continue }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x5450524D, id: UInt32(index)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { references.append(reference) }
            else { model.shortcutError = "\(binding.label) is already in use. Choose another shortcut for \(action)." }
        }
    }

    private func perform(_ index: Int) {
        guard model.recordingShortcut == nil else { return }
        switch index {
        case 0: model.togglePlayback()
        case 1: model.paragraph(-1)
        case 2: model.paragraph(1)
        case 3: model.restart()
        case 4: model.toggleOverlay()
        default: break
        }
    }

    private func capture(_ event: NSEvent) -> NSEvent? {
        guard let action = model.recordingShortcut else { return event }
        if event.keyCode == 53 { model.recordingShortcut = nil; return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else {
            model.shortcutError = "Include Command or Control in your shortcut. Escape cancels."
            return nil
        }
        var modifiers: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); prefix += "⌘" }
        let key = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space" ][Int(event.keyCode)] ?? (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        let binding = ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: prefix + key)
        if model.settings.shortcuts.contains(where: { $0.key != action && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) {
            model.shortcutError = "That shortcut is assigned to another Teleprompter action."
            return nil
        }
        model.recordingShortcut = nil
        model.updateSettings { $0.shortcuts[action] = binding }
        return nil
    }
}
