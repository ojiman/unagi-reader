import AppKit
import SwiftUI
import QuartzCore
import ReaderCore

// A single native text layout replaces per-paragraph SwiftUI geometry/preferences.
@MainActor final class ArticleTextView: NSTextView, NSTextViewDelegate {
    private var paragraphRanges: [NSRange] = []
    private var paragraphYs: [CGFloat] = []
    private var bodyRange: NSRange?
    private var heroRange: NSRange?
    private var heroView: NSView?
    private var installing = false
    var onDisplayBegin: (() -> Void)?
    var onDisplayed: (() -> Void)?
    var onInteraction: (() -> Void)?
    var onScroll: ((String, Double) -> Void)?
    private var didDisplayBody = false
    private var quoteRanges: [(NSRange, CGFloat)] = []
    var onOpenLink: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Loads an image of the feed's HTML; nil leaves the images empty (tests).
    var loadImage: ((URL) async -> NSImage?)?
    private var imageTasks: [Task<Void, Never>] = []

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, frame.width - 84), height: .greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        container.widthTracksTextView = false; container.lineFragmentPadding = 0
        isEditable = false; isSelectable = true; isRichText = true
        delegate = self
        linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        isVerticallyResizable = true; isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 0); maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        drawsBackground = true; backgroundColor = AppPalette.surface
        textContainerInset = NSSize(width: 42, height: 0)
        setAccessibilityLabel(String(localized: "Article Body", bundle: ReaderLocalization.bundle))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureHero(_ view: NSView?) {
        if heroView !== view { heroView?.removeFromSuperview(); heroView = view; if let view { addSubview(view) } }
        positionHero()
    }
    /// Body, title and date follow the article text size. The source name above the title stays a reading-area heading.
    func install(title: String, publisher: String, date: String, paragraphs: [String], unavailable: String?, hero: Bool = false, bodyParagraphs: [BodyParagraph]? = nil, scale: CGFloat = 1) {
        if !paragraphs.isEmpty { onDisplayBegin?() }
        installing = true; defer { installing = false }
        let document = NSMutableAttributedString()
        func append(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false, spacing: CGFloat = 22, scalesWithBody: Bool = true) {
            let factor = scalesWithBody ? scale : 1
            let style = NSMutableParagraphStyle(); style.lineSpacing = (size == 16 ? 8 : 5) * factor; style.paragraphSpacing = spacing * factor
            document.append(NSAttributedString(string: text + "\n", attributes: [.font: NSFont.systemFont(ofSize: size * factor, weight: weight), .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: style]))
        }
        append(publisher, size: ListHeader.fontSize, weight: .semibold, secondary: true, scalesWithBody: false)
        append(title, size: 26, weight: .semibold)
        append(date, size: 12, secondary: true)
        heroRange = nil
        if hero {
            heroRange = NSRange(location: document.length, length: 1)
            let style = NSMutableParagraphStyle(); style.minimumLineHeight = 180; style.maximumLineHeight = 180; style.paragraphSpacing = 22
            document.append(NSAttributedString(string: " \n", attributes: [.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: style]))
        }
        paragraphRanges = []; paragraphYs = []; bodyRange = nil; quoteRanges = []
        imageTasks.forEach { $0.cancel() }; imageTasks = []
        var imageURLs: [String] = []
        let start = document.length
        for (index, paragraph) in paragraphs.enumerated() {
            var range = NSRange(location: document.length, length: (paragraph as NSString).length)
            append(paragraph, size: 16)
            guard let blocks = bodyParagraphs, blocks.indices.contains(index), blocks[index].text == paragraph else { paragraphRanges.append(range); continue }
            let block = blocks[index]
            var indent: CGFloat?
            if block.quoteDepth > 0 {
                let depth = CGFloat(min(block.quoteDepth, 3)) * 20
                let style = NSMutableParagraphStyle(); style.lineSpacing = 8 * scale; style.paragraphSpacing = 22 * scale
                style.headIndent = depth; style.firstLineHeadIndent = depth
                // With its newline: a paragraph of images only has no text, and its images take the style from it.
                document.addAttributes([.paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor], range: NSRange(location: range.location, length: range.length + 1))
                indent = depth
            }
            for link in block.links {
                guard link.location >= 0, link.length > 0, link.location <= range.length, link.length <= range.length - link.location,
                      let url = ArticleURL.link(link.url) else { continue }
                document.addAttributes([.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: range.location + link.location, length: link.length))
            }
            range.length += insertImages(block.images ?? [], into: document, paragraph: range, inset: indent ?? 0)
            imageURLs += (block.images ?? []).map(\.url)
            paragraphRanges.append(range)
            if let indent { quoteRanges.append((range, indent)) }
        }
        if !paragraphs.isEmpty { bodyRange = NSRange(location: start, length: document.length - start) }
        if let unavailable { append(unavailable, size: 16, secondary: true) }
        textStorage?.setAttributedString(document)
        didDisplayBody = false
        layoutDocument()
        needsDisplay = true
        loadImages(imageURLs)
    }

    /// Inserts the paragraph's images at their places (decision 0066) and returns the length added. A block of images only is a paragraph
    /// of its own, so images of separate blocks stand on separate lines.
    private func insertImages(_ images: [BodyImage], into document: NSMutableAttributedString, paragraph range: NSRange, inset: CGFloat) -> Int {
        guard !images.isEmpty else { return 0 }
        let column = textContainer?.containerSize.width ?? 0
        let attributes = document.attributes(at: range.location, effectiveRange: nil).filter { [.font, .paragraphStyle].contains($0.key) }
        var added = 0
        // From the last to the first, so earlier offsets stay right and images at one offset keep their order.
        for image in images.enumerated().sorted(by: { ($0.element.location, $0.offset) > ($1.element.location, $1.offset) }).map(\.element) {
            let cell = BodyImageCell(url: image.url, width: image.width, height: image.height, inset: inset)
            cell.fit(to: column)
            let attachment = NSTextAttachment(); attachment.attachmentCell = cell
            let piece = NSMutableAttributedString(attachment: attachment)
            if let link = image.link.flatMap({ ArticleURL.link($0) }) { piece.addAttribute(.link, value: link, range: NSRange(location: 0, length: piece.length)) }
            piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
            document.insert(piece, at: range.location + min(max(0, image.location), range.length))
            added += piece.length
        }
        return added
    }
    private func loadImages(_ urls: [String]) {
        guard let loadImage else { return }
        for value in Set(urls) {
            guard let url = ArticleURL.validated(value) else { continue }
            imageTasks.append(Task { [weak self] in
                let image = await loadImage(url)
                guard !Task.isCancelled else { return }
                self?.show(image, for: value)
            })
        }
    }
    /// An image arrived, or failed (nil): a failed one gives back the box reserved for it. When a size changes, the text is laid out again
    /// and the paragraph being read stays where it was.
    func show(_ image: NSImage?, for url: String) {
        guard let storage = textStorage else { return }
        let column = textContainer?.containerSize.width ?? 0
        var changed: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let cell = (value as? NSTextAttachment)?.attachmentCell as? BodyImageCell, cell.url == url else { return }
            if image.map({ cell.arrive($0, column: column) }) ?? cell.fail() { changed.append(range) }
            else { layoutManager?.invalidateDisplay(forCharacterRange: range) }
        }
        guard !changed.isEmpty, let manager = layoutManager else { return }
        let kept = enclosingScrollView != nil && !paragraphRanges.isEmpty ? readingPosition() : nil
        for range in changed { manager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil) }
        paragraphYs = []
        if let kept { restore(anchor: kept.anchor, offset: kept.offset) } else { layoutDocument() }
        needsDisplay = true
    }
    /// The text of these ranges as the person reads it: images left out, their line breaks as line breaks.
    func plainText(_ ranges: [NSRange]) -> String {
        let source = string as NSString
        return ranges.filter { $0.length > 0 && NSMaxRange($0) <= source.length }
            .map { source.substring(with: $0).replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\u{2028}", with: "\n") }
            .joined(separator: "\n")
    }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return super.writeSelection(to: pboard, type: type) }
        return pboard.setString(plainText(selectedRanges.map(\.rangeValue)), forType: .string)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        let previous = widthChanged && !installing && !paragraphRanges.isEmpty ? readingPosition() : nil
        super.setFrameSize(newSize)
        if widthChanged {
            let width = max(1, min(670, newSize.width - 84))
            textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage?.length ?? 0)) { value, _, _ in
                ((value as? NSTextAttachment)?.attachmentCell as? BodyImageCell)?.fit(to: width)
            }
            textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            textContainerInset = NSSize(width: max(42, (newSize.width - width) / 2), height: 0)
            paragraphYs = []
            layoutDocument()
            if let previous { restore(anchor: previous.anchor, offset: previous.offset) }
        }
    }

    private func layoutDocument() {
        guard let manager = layoutManager, let container = textContainer else { return }
        manager.ensureLayout(for: container)
        let height = max(enclosingScrollView?.contentSize.height ?? 0, manager.usedRect(for: container).maxY + textContainerInset.height + 44)
        if abs(frame.height - height) > 0.5 { super.setFrameSize(NSSize(width: frame.width, height: height)) }
        positionHero()
    }
    private func positionHero() {
        guard let heroView, let heroRange, let manager = layoutManager, let container = textContainer else { self.heroView?.isHidden = true; return }
        let glyphs = manager.glyphRange(forCharacterRange: heroRange, actualCharacterRange: nil)
        let rect = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        heroView.isHidden = false
        heroView.frame = NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y + rect.minY, width: container.containerSize.width, height: 180)
    }
    private func paragraphPositions() -> [CGFloat] {
        if paragraphYs.count == paragraphRanges.count { return paragraphYs }
        guard let manager = layoutManager, let container = textContainer else { return [] }
        paragraphYs = paragraphRanges.map { range in
            let first = NSRange(location: range.location, length: min(1, range.length))
            let glyph = manager.glyphRange(forCharacterRange: first, actualCharacterRange: nil)
            return manager.boundingRect(forGlyphRange: glyph, in: container).minY + textContainerOrigin.y
        }
        return paragraphYs
    }
    func readingPosition() -> (anchor: String, offset: Double) {
        let y = enclosingScrollView?.contentView.bounds.minY ?? 0
        let positions = paragraphPositions()
        // Sorted paragraph positions keep scroll bookkeeping off the SwiftUI update graph.
        var lower = 0, upper = positions.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if positions[middle] <= y { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return ("top", Double(max(0, y))) }
        return ("paragraph-\(lower - 1)", Double(max(0, y - positions[lower - 1])))
    }
    func restore(anchor: String?, offset: Double) {
        layoutDocument()
        let positions = paragraphPositions()
        let index = anchor.flatMap { Int($0.replacingOccurrences(of: "paragraph-", with: "")) }
        let base = index.flatMap { positions.indices.contains($0) ? positions[$0] : nil } ?? 0
        guard let scroll = enclosingScrollView else { return }
        let target = min(max(0, frame.height - scroll.contentSize.height), max(0, base + offset))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: target)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    var hasVisibleBody: Bool {
        guard let bodyRange, let manager = layoutManager, let container = textContainer else { return false }
        let visible = visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return NSIntersectionRange(bodyRange, characters).length > 0
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let manager = layoutManager, let container = textContainer {
            NSColor.separatorColor.setFill()
            for (range, indent) in quoteRanges {
                let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                let line = NSRect(x: textContainerOrigin.x + indent - 12, y: textContainerOrigin.y + rect.minY, width: 2, height: rect.height)
                if line.intersects(dirtyRect) { line.fill() }
            }
        }
        guard !didDisplayBody, window != nil, hasVisibleBody else { return }
        didDisplayBody = true
        // SwiftUI state/storage writes happen after the native draw, never inside its update.
        let callback = onDisplayed
        DispatchQueue.main.async { callback?() }
    }
    override func mouseDown(with event: NSEvent) { onInteraction?(); super.mouseDown(with: event) }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let value = (link as? URL)?.absoluteString ?? (link as? String)
        guard let value, let url = ArticleURL.link(value) else { return true }
        _ = onOpenLink(url)
        return true
    }
    func recordScroll() {
        guard !installing else { return }
        let position = readingPosition(); onScroll?(position.anchor, position.offset)
    }
}

extension ArticleTextView {
    /// The text the person selected in the article, when the article has the keyboard (「記事をノートに送る」, specification 3.3).
    /// Several selected pieces are joined by line breaks.
    static func selectedText(in window: NSWindow?) -> String? {
        guard let view = window?.firstResponder as? ArticleTextView else { return nil }
        let text = view.plainText(view.selectedRanges.map(\.rangeValue))
        return text.isEmpty ? nil : text
    }
}

struct NativeArticleText: NSViewRepresentable {
    let articleID: UUID
    let title: String
    let publisher: String
    let date: String
    let paragraphs: [String]
    let unavailable: String?
    let initialAnchor: String?
    let initialOffset: Double
    let reduceMotion: Bool
    let onScroll: (String, Double) -> Void
    let onInteraction: () -> Void
    let onDisplayBegin: () -> Void
    let onDisplayed: () -> Void
    var imageLoader: ReaderImageLoader? = nil
    var heroURL: URL? = nil
    var bodyParagraphs: [BodyParagraph]? = nil
    var pageForward = true
    /// The article's text size against the standard one (specification 3.7).
    var textScale: CGFloat = 1

    @MainActor final class Coordinator {
        var signature: [String] = []
        var textScale: CGFloat = 1
        var sepia = ThemeState.shared.sepia
        var bodyParagraphs: [BodyParagraph]?
        nonisolated(unsafe) var observer: NSObjectProtocol?
        var restoring = false
        var hero: NSHostingView<ArticleImageView>?
        private var articleID: UUID?
        func animatePage(in scroll: NSScrollView, articleID: UUID, forward: Bool, reduceMotion: Bool) {
            let changed = self.articleID != nil && self.articleID != articleID
            self.articleID = articleID
            scroll.wantsLayer = true
            if reduceMotion { scroll.layer?.removeAnimation(forKey: "article-motion"); return }
            guard changed else { return }
            scroll.layer?.removeAnimation(forKey: "article-motion")
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = forward ? -64.0 : 64.0; move.toValue = 0.0; move.duration = 0.22
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.88; fade.toValue = 1.0; fade.duration = 0.22
            let page = CAAnimationGroup()
            page.animations = [move, fade]; page.duration = 0.22
            page.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scroll.layer?.add(page, forKey: "article-motion")
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // The reader proposes a viewport; document height must never size the split pane.
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 600, height: 400))
    }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ArticleScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = true; scroll.backgroundColor = AppPalette.surface
        let text = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = text
        scroll.contentView.postsBoundsChangedNotifications = true
        let coordinator = context.coordinator
        coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak text, weak coordinator] _ in
            MainActor.assumeIsolated { if coordinator?.restoring == false { text?.recordScroll() } }
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? ArticleTextView else { return }
        // The surface's colour depends on the theme (Sepia); reading it here redraws the article when it changes.
        if context.coordinator.sepia != ThemeState.shared.sepia {
            context.coordinator.sepia = ThemeState.shared.sepia
            scroll.needsDisplay = true; text.needsDisplay = true
        }
        let signature = [articleID.uuidString, title, publisher, date, unavailable ?? "", heroURL?.absoluteString ?? "", "\(textScale)"] + paragraphs
        // Only the size changed: the paragraph at the top stays at the top (specification 3.7).
        let kept = context.coordinator.signature.first == articleID.uuidString && context.coordinator.textScale != textScale
            ? text.readingPosition() : nil
        let ratio = Double(textScale / context.coordinator.textScale)
        let changed = signature != context.coordinator.signature || bodyParagraphs != context.coordinator.bodyParagraphs
        if changed { text.recordScroll() }
        text.onScroll = onScroll; text.onInteraction = onInteraction; text.onDisplayBegin = onDisplayBegin; text.onDisplayed = onDisplayed
        text.loadImage = imageLoader.map { loader in
            { url in (try? await loader.image(url: url, at: .now)).flatMap { $0 }.flatMap { NSImage(data: $0) } }
        }
        (scroll as? ArticleScrollView)?.onInteraction = onInteraction
        if let imageLoader, let heroURL {
            let image = ArticleImageView(loader: imageLoader, articleID: articleID, url: heroURL, size: CGSize(width: 0, height: 180))
            if let hero = context.coordinator.hero { if changed { hero.rootView = image } }
            else {
                let hero = NSHostingView(rootView: image)
                // ArticleTextView owns the fixed frame; intrinsic-size constraints
                // must not resize the surrounding text layout when an image arrives.
                hero.sizingOptions = []
                context.coordinator.hero = hero
            }
            text.configureHero(context.coordinator.hero)
        } else { text.configureHero(nil); context.coordinator.hero = nil }
        if reduceMotion { scroll.layer?.removeAnimation(forKey: "article-motion") }
        guard changed else { return }
        context.coordinator.restoring = true
        context.coordinator.signature = signature
        context.coordinator.bodyParagraphs = bodyParagraphs
        context.coordinator.textScale = textScale
        text.install(title: title, publisher: publisher, date: date, paragraphs: paragraphs, unavailable: unavailable, hero: heroURL != nil, bodyParagraphs: bodyParagraphs, scale: textScale)
        if let kept { text.restore(anchor: kept.anchor, offset: kept.offset * ratio); text.recordScroll() }
        else { text.restore(anchor: initialAnchor, offset: initialOffset) }
        context.coordinator.restoring = false
        context.coordinator.animatePage(in: scroll, articleID: articleID, forward: pageForward, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? ArticleTextView)?.recordScroll()
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer); coordinator.observer = nil }
    }
}

private final class ArticleScrollView: NSScrollView {
    var onInteraction: (() -> Void)?
    override func scrollWheel(with event: NSEvent) { onInteraction?(); super.scrollWheel(with: event) }
}
