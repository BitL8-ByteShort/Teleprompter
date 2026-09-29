import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var model: AppModel
    @State private var showSetup = false
    private let accent = Color(red: 0.20, green: 0.68, blue: 0.57)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "text.viewfinder").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Teleprompter").font(.title2.weight(.semibold))
                    Text("Built for your next take").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(model.running ? accent : .secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(model.stateLabel).font(.callout.weight(.medium))
                }.padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary, in: Capsule())
            }.padding(24)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("SCRIPT", systemImage: "doc.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.script.tokens.count) words · ~\(model.estimatedMinutes) min").font(.caption).foregroundStyle(.secondary)
                    }
                    ScriptEditor(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
                    HStack {
                        Text(model.saveStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Read from cursor", systemImage: "text.cursor") { model.readFromSelection() }
                            .help("Place the cursor in your script, then resume reading there after a countdown")
                    }
                }.padding(24).frame(minWidth: 430)
                inspector.frame(width: 300)
            }
            Divider()
            VStack(spacing: 12) {
                ProgressView(value: model.progress).tint(accent)
                HStack(spacing: 12) {
                    Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                    Button { model.paragraph(-1) } label: { Image(systemName: "backward.end.fill") }.help("Previous paragraph")
                    Button { model.paragraph(1) } label: { Image(systemName: "forward.end.fill") }.help("Next paragraph")
                    Spacer()
                    Text(model.settings.shortcuts["play"]?.label ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Button { model.togglePlayback() } label: {
                        Label(model.running ? "Pause" : "Start reading", systemImage: model.running ? "pause.fill" : "play.fill")
                            .frame(width: 125)
                    }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large).disabled(model.script.tokens.isEmpty)
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button("Import", systemImage: "square.and.arrow.down") { importScript() }
                Button("Export", systemImage: "square.and.arrow.up") { exportScript() }
                Button(model.overlayVisible ? "Hide prompter" : "Show prompter", systemImage: model.overlayVisible ? "eye" : "eye.slash") { model.toggleOverlay() }
                Button("Recording setup", systemImage: "video.badge.checkmark") { showSetup = true }
            }
        }
        .sheet(isPresented: $showSetup) { RecordingSetupView() }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("PACE", icon: "metronome")
                    Picker("Pacing mode", selection: setting(\.mode)) {
                        Text("Auto-scroll").tag(ScrollMode.automatic)
                        Text("Voice-follow").tag(ScrollMode.voice)
                    }.pickerStyle(.segmented).labelsHidden()
                    if model.settings.mode == .automatic {
                        control("Reading speed", value: "\(Int(model.settings.wpm)) wpm") {
                            Slider(value: setting(\.wpm), in: 60...240, step: 5).accessibilityLabel("Reading speed")
                        }
                        Text("A steady pace, with a three-second lead-in.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Microphone", selection: setting(\.microphoneID)) {
                            Text("System default").tag("")
                            ForEach(model.microphones) { Text($0.name).tag($0.id) }
                            if !model.settings.microphoneID.isEmpty && !model.microphones.contains(where: { $0.id == model.settings.microphoneID }) {
                                Text("Disconnected microphone").tag(model.settings.microphoneID)
                            }
                        }
                        Button("Refresh microphones", systemImage: "arrow.clockwise") { model.refreshMicrophones() }.font(.caption)
                        ProgressView(value: Double(model.microphoneLevel)).tint(accent).accessibilityLabel("Microphone input level")
                        Text(model.speechStatus).font(.caption).foregroundStyle(.secondary)
                        Text("Recognized on this Mac. Audio is never saved. Pauses and ad-libs hold your place.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            if model.settings.mode == .voice {
                                Button("Use auto-scroll") { model.useAutoScroll() }
                                Button("Microphone permissions") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                                }.font(.caption)
                            } else { Button("Dismiss") { model.errorMessage = nil }.font(.caption) }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("READING PANEL", icon: "rectangle.topthird.inset.filled")
                    control("Text size", value: "\(Int(model.settings.fontSize)) pt") {
                        Slider(value: setting(\.fontSize), in: 24...64, step: 2).accessibilityLabel("Text size")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text alignment").font(.callout)
                        Picker("Text alignment", selection: setting(\.alignment)) {
                            Text("Left").tag(ReadingAlignment.left)
                            Text("Center").tag(ReadingAlignment.center)
                            Text("Right").tag(ReadingAlignment.right)
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    control("Panel width", value: "\(Int(model.settings.width)) pt") {
                        Slider(value: setting(\.width), in: 320...720, step: 20).accessibilityLabel("Panel width")
                    }
                    Stepper("Visible lines: \(model.settings.lineCount)", value: setting(\.lineCount), in: 2...4)
                    control("Background", value: "\(Int(model.settings.opacity * 100))%") {
                        Slider(value: setting(\.opacity), in: 0.35...1, step: 0.05).accessibilityLabel("Background opacity")
                    }
                    Text("Centered under your MacBook camera. Adjust from your recording position, 2–4 feet away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                DisclosureGroup("Keyboard shortcuts") {
                    VStack(spacing: 10) {
                        ForEach([("play", "Play / pause"), ("previous", "Previous paragraph"), ("next", "Next paragraph"), ("restart", "Restart"), ("overlay", "Show / hide")], id: \.0) { action, title in
                            HStack {
                                Text(title).font(.caption)
                                Spacer()
                                Button(model.recordingShortcut == action ? "Press keys…" : (model.settings.shortcuts[action]?.label ?? "Set")) {
                                    model.recordingShortcut = action
                                }.font(.caption.monospaced()).frame(minWidth: 70)
                            }
                        }
                        if model.recordingShortcut != nil { Text("Include ⌘ or ⌃. Escape cancels.").font(.caption).foregroundStyle(.secondary) }
                        if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button("Restore defaults") { model.recordingShortcut = nil; model.updateSettings { $0.shortcuts = ShortcutBinding.defaults } }.font(.caption)
                    }.padding(.top, 10)
                }
                Button("Set up Cap recording", systemImage: "video") { showSetup = true }.font(.callout)
            }.padding(20)
        }.background(.quaternary.opacity(0.35))
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
    private func control<Content: View>(_ title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }.font(.callout)
            content()
        }
    }
    private func setting<Value>(_ key: WritableKeyPath<PrompterSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: key] }, set: { value in model.updateSettings { $0[keyPath: key] = value } })
    }
    private func importScript() {
        model.pause()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.edit(try String(contentsOf: url, encoding: .utf8)); model.restart() }
        catch { model.errorMessage = "Could not read that text file: \(error.localizedDescription)" }
    }
    private func exportScript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "YouTube Script.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.text.write(to: url, atomically: true, encoding: .utf8) }
        catch { model.errorMessage = "Could not export the script: \(error.localizedDescription)" }
    }
}

struct RecordingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Keep your script out of the video", systemImage: "video.badge.checkmark").font(.title2.weight(.semibold))
            Text("Cap · recommended").font(.headline)
            Text("1. Open Teleprompter and show the reading panel.\n2. In Cap, open Settings → General → Excluded windows.\n3. Add Teleprompter. Leave its reading panel open before starting each take.\n4. Record a short Studio sample with your camera and microphone, then check the saved video.")
                .lineSpacing(7)
            Text("Cap applies the exclusion to this app. Keep the app running during a take; restarting it creates new windows and requires a new recording.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("OBS & macOS capture").font(.headline)
            Text("In OBS, capture only the app/window you are demonstrating or configure capture exclusions. With macOS screen capture, select an area below the panel or record the external display. Check a sample before a full take; this app cannot hide itself from every recorder.")
                .font(.callout).foregroundStyle(.secondary)
            Text("For voice-follow, select the microphone you speak into. Cap and Teleprompter both need microphone access; Teleprompter never opens your camera.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Cap") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Cap.app"), configuration: .init()) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 530)
    }
}
