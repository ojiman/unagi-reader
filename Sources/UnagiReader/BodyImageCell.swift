import AppKit

/// An image of the feed's HTML inside the article text (decision 0066). Its size is fixed until the image arrives: the feed's width and
/// height fitted to the column, or nothing at all when the feed gives none, so a late or failed image never leaves a gap that jumps.
/// Clicks go to the text view, which opens the image's link like any other.
final class BodyImageCell: NSTextAttachmentCell {
    let url: String
    /// The quote's indent: the image fits the column less this.
    let inset: CGFloat
    private(set) var picture: NSImage?
    /// The size the image wants: the feed's, then the image's own once it has arrived.
    private var natural: NSSize?
    private var size = NSSize(width: 1, height: 1)

    init(url: String, width: Int?, height: Int?, inset: CGFloat = 0) {
        self.url = url; self.inset = inset
        if let width, let height { natural = NSSize(width: width, height: height) }
        super.init(imageCell: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Fits the image to the column; true when its size changed.
    @discardableResult func fit(to column: CGFloat) -> Bool {
        let column = column - inset
        guard let natural, natural.width > 0, natural.height > 0, column > 0 else { return false }
        let scale = min(1, column / natural.width)
        let fitted = NSSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
        defer { size = fitted }
        return fitted != size
    }
    /// The image did not come (failed, offline): the box reserved for it goes, so no gap is left. True when its size changed.
    func fail() -> Bool {
        picture = nil; natural = nil
        defer { size = NSSize(width: 1, height: 1) }
        return size != NSSize(width: 1, height: 1)
    }
    /// The arrived image; true when its size changed.
    func arrive(_ image: NSImage, column: CGFloat) -> Bool {
        picture = image
        natural = image.size
        return fit(to: column)
    }

    /// The SDK declares this nonisolated; the text view's layout calls it on the main thread (no background layout).
    override nonisolated func cellSize() -> NSSize { MainActor.assumeIsolated { size } }
    override func cellBaselineOffset() -> NSPoint { .zero }
    override func wantsToTrackMouse() -> Bool { false }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if let picture {
            picture.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if size.width > 1 {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
            cellFrame.fill()
        }
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}
