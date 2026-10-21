import SwiftUI
import ReaderCore
import AppKit

/// The list filter in the list's band (specification 3.1.4, decision 0057): a magnifier at the right; clicking it, or `/`, grows the
/// system's search field out of it toward the left. The field stays while it has text (and the filter with it); left empty, a click
/// elsewhere turns it back into the magnifier.
struct ListFilterBar: View {
    @Binding var text: String
    let shown: Bool
    let open: () -> Void
    /// `Esc` in the empty field: closes it and gives the list the keyboard.
    let close: () -> Void
    /// The keyboard went elsewhere: closes the field and leaves the keyboard where the person clicked.
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The opening and closing motion: the field grows out of the magnifier (none with Reduce Motion).
    static let motion = Animation.snappy(duration: 0.25)

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                if shown {
                    ListFilterField(text: $text, close: close, dismiss: dismiss)
                        .frame(height: ArticleBand.controlLine)
                        .transition(.opacity)
                } else {
                    BandButton(id: "filter", symbol: "magnifyingglass", help: String(localized: "Filter Articles (/)", bundle: ReaderLocalization.bundle), label: String(localized: "Filter Articles", bundle: ReaderLocalization.bundle), action: open)
                        .transition(.opacity)
                }
            }
            // The field's width grows from the magnifier's to the whole band.
            .frame(maxWidth: shown ? .infinity : 28, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: ArticleBand.controlLine)
        .padding(.top, ArticleBand.controlTop)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Self.motion, value: shown)
    }
}

/// The system's search field. The list follows its text, but not while Japanese text is being composed in it: the text is handed on
/// only when the field's editor has no marked text, and again when the composition is committed. `Esc` in an empty field, or the keyboard
/// going elsewhere while it is empty, closes it.
struct ListFilterField: NSViewRepresentable {
    @Binding var text: String
    let close: () -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .large                                         // as high as the band's buttons
        field.placeholderString = String(localized: "Filter", bundle: ReaderLocalization.bundle)
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        // The ✕ clears the field through its action, with no text-change notice.
        field.target = context.coordinator; field.action = #selector(Coordinator.searched(_:))
        field.stringValue = text
        field.setAccessibilityLabel(String(localized: "Filter Articles", bundle: ReaderLocalization.bundle))
        // Take the keyboard when the field appears (`/` or the magnifier).
        DispatchQueue.main.async { [weak field] in field?.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !composing, field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ListFilterField
        init(_ parent: ListFilterField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            Self.hand(field.stringValue, from: field, to: &parent.text)
        }
        /// The text is handed to the list only when nothing is being composed.
        static func hand(_ value: String, from field: NSSearchField, to text: inout String) {
            guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, text != value else { return }
            text = value
        }
        @objc func searched(_ field: NSSearchField) { Self.hand(field.stringValue, from: field, to: &parent.text) }
        /// The keyboard went elsewhere (a click anywhere): an empty field turns back into the magnifier; one with text stays open.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            Self.hand(field.stringValue, from: field, to: &parent.text)
            if field.stringValue.isEmpty { parent.dismiss() }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText(), textView.string.isEmpty else { return false }
            parent.close()
            return true
        }
    }
}
