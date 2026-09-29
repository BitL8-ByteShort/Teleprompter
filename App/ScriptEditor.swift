import AppKit
import SwiftUI

struct ScriptEditor: NSViewRepresentable {
    let model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let text = NSTextView()
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.allowsUndo = true
        text.font = .systemFont(ofSize: 19)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 20, height: 20)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.delegate = context.coordinator
        text.string = model.text
        text.setAccessibilityLabel("YouTube script")
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, text.string != model.text else { return }
        let selection = text.selectedRange()
        text.string = model.text
        text.setSelectedRange(NSRange(location: min(selection.location, (model.text as NSString).length), length: 0))
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        init(model: AppModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            if let text = notification.object as? NSTextView { model.edit(text.string) }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let text = notification.object as? NSTextView { model.selection = text.selectedRange() }
        }
    }
}
