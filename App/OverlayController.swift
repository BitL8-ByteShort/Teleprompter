import AppKit
import SwiftUI

private final class ReadingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    let panel: NSPanel
    private let model: AppModel
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        panel = ReadingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Teleprompter Reading Panel"
        panel.identifier = NSUserInterfaceItemIdentifier("teleprompter-reading-panel")
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: ReadingPanelView(model: model))
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        model.overlayChanged = { [weak self] in self?.update() }
        update()
    }

    func update() {
        guard model.overlayVisible else { panel.orderOut(nil); return }
        let screen = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }
        guard let screen else {
            panel.orderOut(nil)
            model.pause()
            model.errorMessage = "Open the MacBook display to place the prompter beneath its camera."
            return
        }
        let height = model.lineHeight * Double(model.settings.lineCount) + 56
        let frame = OverlayGeometry.frame(screen: screen.frame, safeTop: screen.safeAreaInsets.top, visibleTop: screen.visibleFrame.maxY, width: model.settings.width, height: height)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
}

struct ReadingPanelView: View {
    @Bindable var model: AppModel
    @State private var hovered = false
    private var offset: Double {
        model.readingOffset
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if model.script.tokens.isEmpty || model.playback.state == .finished {
                    Text(model.playback.state == .finished ? "Take complete." : "Paste your script in Teleprompter.")
                        .font(.system(size: model.settings.fontSize, weight: .medium))
                        .multilineTextAlignment(model.settings.alignment.textAlignment)
                        .frame(maxWidth: .infinity, alignment: model.settings.alignment.frameAlignment)
                        .padding(.horizontal, 24)
                } else {
                    // Render only the nearby lines. A long script must not add thousands
                    // of SwiftUI views to a recording session's frame budget.
                    let start = max(0, Int(offset / model.lineHeight))
                    let end = min(model.layout.lines.count, start + model.settings.lineCount + 2)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.layout.lines[start..<max(start, end)])) { line in
                            Text(line.text)
                                .font(.system(size: model.settings.fontSize, weight: .medium))
                                .foregroundStyle(line.id == start ? .white : .white.opacity(0.65))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: model.lineHeight, maxHeight: model.lineHeight, alignment: model.settings.alignment.frameAlignment)
                                .contentShape(Rectangle())
                                .onTapGesture { model.resume(from: line.firstWord) }
                                .help("Resume reading from this line")
                        }
                    }
                    .padding(.horizontal, 24)
                    .offset(y: Double(start) * model.lineHeight - offset)
                }
            }
            .frame(height: model.lineHeight * Double(model.settings.lineCount), alignment: .top)
            .clipped()
            .overlay(alignment: .topLeading) {
                Capsule().fill(.mint).frame(width: 3, height: model.lineHeight * 0.55).padding(.leading, 9).padding(.top, 10)
            }
            HStack(spacing: 15) {
                Button { model.paragraph(-1) } label: { Image(systemName: "backward.end.fill") }.help("Previous paragraph")
                Button { model.togglePlayback() } label: { Image(systemName: model.running ? "pause.fill" : "play.fill") }.help("Play or pause")
                Button { model.paragraph(1) } label: { Image(systemName: "forward.end.fill") }.help("Next paragraph")
                Spacer()
                Text(model.stateLabel).font(.caption)
                Button { model.toggleOverlay() } label: { Image(systemName: "eye.slash") }.help("Hide prompter")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 24)
            .frame(height: 32)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.black.opacity(model.settings.opacity), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)) }
        .overlay {
            if model.playback.state == .countdown || model.isPreparing {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.92))
                    VStack(spacing: 4) {
                        if model.isPreparing { ProgressView().controlSize(.small) }
                        else { Text("\(Int(ceil(model.playback.countdown)))").font(.system(size: 60, weight: .semibold, design: .rounded)) }
                        Text(model.isPreparing ? model.speechStatus : "Look toward the camera").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }.foregroundStyle(.white)
                }
            }
        }
        .onHover { hovered = $0 }
        .preferredColorScheme(.dark)
        .accessibilityLabel("Teleprompter reading panel")
    }
}

private extension ReadingAlignment {
    var frameAlignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}
