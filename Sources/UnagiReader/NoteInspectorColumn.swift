import SwiftUI
import AppKit
import Observation
import ReaderCore

/// Window geometry stays outside `ReaderView`'s state; only the column modifiers read each resize.
@MainActor @Observable final class WindowSpace {
    var width: Double = 1_280
    /// The settled visible list width; folding and returning widths do not replace it.
    var listWidth: Double = NotePanelWidth.listDefaultWidth
    /// The note panel's width now.
    var noteWidth: Double = NotePanelWidth.defaultWidth
}

/// The note panel's column: as wide as the person made it, but never so wide that the article loses its 360 pt, or the list the width it has
/// when it is shown (at least 280 pt; its room is kept also while it is folded). A window that is too narrow for the saved width squeezes
/// the panel; the saved width stays (specification 3.5).
struct NoteInspectorColumn<Panel: View>: View {
    let space: WindowSpace
    let startingWidth: Double
    @ViewBuilder let panel: (Double) -> Panel

    var body: some View {
        let limit = NotePanelWidth.maximum(windowWidth: space.width, listWidth: space.listWidth)
        panel(limit).background(NoteColumnHold())
            .inspectorColumnWidth(min: NotePanelWidth.range.lowerBound, ideal: min(startingWidth, limit), max: limit)
    }
}

/// Keeps the note panel from folding when the person drags its edge (specification 3.5, #370).
///
/// The system's inspector folds its column when the edge is dragged past the panel's minimum, and SwiftUI then reports the panel closed.
/// This view finds the AppKit split view item that holds the panel and turns off its collapsing from a drag; the panel still opens and
/// closes through `inspector(isPresented:)`. A workaround kept in this one file, like `ListColumnCollapse`.
struct NoteColumnHold: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.hold() }

    @MainActor final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hold()
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            hold()
        }
        func hold() {
            guard let item = SplitViewItemLookup(holding: self)?.item else { return }
            if item.canCollapse { item.canCollapse = false }
        }
    }
}
