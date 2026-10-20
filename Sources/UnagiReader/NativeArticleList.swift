import AppKit
import SwiftUI
import ReaderCore

// Stable native rows avoid rebuilding SwiftUI's 10,000-row ID/preference graph on selection.
struct NativeArticleList: NSViewRepresentable {
    let ids: [UUID]
    let article: (UUID) -> Article?
    let feedTitle: (Article) -> String
    @Binding var selection: UUID?
    let initialTop: UUID?
    let focus: Bool
    let shortcutsEnabled: Bool
    let onTop: (UUID) -> Void
    let onKey: (String) -> Void
    var imageLoader: ReaderImageLoader? = nil
    var iconURL: (Article) -> URL? = { _ in nil }
    var initialTopOffset: Double = 0
    var onTopOffset: ((UUID, Double) -> Void)? = nil
    /// Room above the first row for the title block (`ListHeader`), on top of the toolbar's own inset.
    var headerInset: CGFloat = 0

    /// The list is drawn on the same surface as the article and the note.
    static func applySurface(scroll: NSScrollView, table: NSTableView) {
        table.backgroundColor = AppPalette.surface
        scroll.drawsBackground = true; scroll.backgroundColor = AppPalette.surface
    }

    /// The table's own setup. Tests use it too, so they measure the same table the app builds.
    static func configure(_ table: Table) {
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: .init("article")))
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = Metrics.rowHeight
        table.intercellSpacing = .init(width: 0, height: 0)
        table.style = .inset
        table.allowsMultipleSelection = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ScrollView()
        let table = Table()
        Self.configure(table)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.setAccessibilityLabel(String(localized: "Article List", bundle: ReaderLocalization.bundle))
        table.keyHandler = { [weak coordinator = context.coordinator] key in
            guard let coordinator, coordinator.parent.shortcutsEnabled else { return false }
            coordinator.parent.onKey(key); return true
        }
        scroll.documentView = table
        Self.applySurface(scroll: scroll, table: table)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.additionalSafeAreaInsets = NSEdgeInsets(top: headerInset, left: 0, bottom: 0, right: 0)
        context.coordinator.table = table
        context.coordinator.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated { coordinator?.recordTop() }
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // The surface's colour depends on the theme (Sepia); reading it here redraws the list when it changes.
        if context.coordinator.sepia != ThemeState.shared.sepia {
            context.coordinator.sepia = ThemeState.shared.sepia
            scroll.needsDisplay = true; context.coordinator.table?.redrawAll()
        }
        if scroll.additionalSafeAreaInsets.top != headerInset { scroll.additionalSafeAreaInsets = NSEdgeInsets(top: headerInset, left: 0, bottom: 0, right: 0) }
        context.coordinator.update(self)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.table?.delegate = nil; coordinator.table?.dataSource = nil
    }

    @MainActor final class ScrollView: NSScrollView {
        override func tile() {
            super.tile()
            // A zero-width fold can leave the table's old column width as its minimum (#371).
            guard let table = documentView as? Table, contentSize.width > 0,
                  abs(table.frame.width - contentSize.width) > 0.5 else { return }
            table.setFrameSize(NSSize(width: contentSize.width, height: table.frame.height))
        }
    }

    /// A row that is selected in a quiet way: a rounded neutral gray, also when the list has the keyboard focus. The text keeps its
    /// own colours (`isEmphasized` stays false, so the cells never switch to the white-on-blue style).
    @MainActor final class SoftRow: NSTableRowView {
        override var isEmphasized: Bool { get { false } set { } }
        /// `.raised` tells the cell "I am selected, in the quiet way" (the system only has `.emphasized` for the blue selection).
        override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .raised : .normal }
        override func drawSelection(in dirtyRect: NSRect) {
            guard isSelected else { return }
            AppPalette.selection.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
    }

    /// The vertical rhythm of a row (points), in one place so the table's row height and the cell's layout cannot drift apart.
    enum Metrics {
        /// From the side edge of the list to the text of a row: the system's inset table style plus the cell's own 12 pt. The title above
        /// the list (`ListHeader`) uses the same number so that the title and the rows share one edge. A test measures it in a real table,
        /// so a change on either side fails there instead of drifting.
        static let contentMargin: CGFloat = 28
        static let rowHeight: CGFloat = 108
        static let topInset: CGFloat = 14
        static let bottomInset: CGFloat = 14
        static let headerGap: CGFloat = 6
        static let textGap: CGFloat = 4
        static let bodyHeight: CGFloat = 56
    }

    @MainActor final class Table: NSTableView {
        var keyHandler: ((String) -> Bool)?
        var focusWhenAttached = false
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            allowsTypeSelect = false                                    // a letter that is not a shortcut must not jump to a row (#226)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            ReaderPerformance.listDrawn(rows: numberOfRows, visible: window?.isVisible == true && !visibleRect.isEmpty)
        }
        /// Every row again, after the theme changed the surface's colour.
        func redrawAll() {
            needsDisplay = true
            enumerateAvailableRowViews { row, _ in row.needsDisplay = true; row.subviews.forEach { $0.needsDisplay = true } }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if focusWhenAttached { window?.makeFirstResponder(self) }
        }
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               let key = event.charactersIgnoringModifiers, ReaderShortcuts.readingLetters.contains(key),
               keyHandler?(key) == true { return }
            super.keyDown(with: event)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeArticleList
        var sepia = ThemeState.shared.sepia
        weak var table: Table?
        weak var scroll: NSScrollView?
        var observer: NSObjectProtocol?
        var ids: [UUID] = []
        var priorSelection: UUID?
        var priorFocus = false
        var synchronizing = false
        /// How the last update put new articles in (for tests): nil when it did not insert, `[]` when nothing visible moved.
        private(set) var lastInsertion: NSTableView.AnimationOptions?
        var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        init(_ parent: NativeArticleList) { self.parent = parent }
        func update(_ parent: NativeArticleList) {
            guard let table else { return }
            synchronizing = true
            let selectionChanged = priorSelection != parent.selection
            let firstLoad = ids.isEmpty
            let topRow = table.rows(in: table.visibleRect).location
            let topID = ids.indices.contains(topRow) ? ids[topRow] : nil
            let topOffset = topID == nil ? 0 : (scroll?.contentView.bounds.minY ?? 0) - table.rect(ofRow: topRow).minY
            self.parent = parent
            let nextIDs = parent.ids
            let idsChanged = ids != nextIDs
            // New articles go in where they land, with the system's table motion (specification 3.2). Any other change reloads the rows.
            let inserted = idsChanged && !firstLoad && !selectionChanged ? ListInsertion.insertedIndexes(old: ids, new: nextIDs) : nil
            let atTop = scroll.map { $0.contentView.bounds.minY <= -$0.contentView.contentInsets.top + 1 } ?? false
            lastInsertion = nil
            if let inserted, atTop {
                // At the top they slide in and push the rows below them down; with Reduce Motion they fade in.
                ids = nextIDs
                let motion: NSTableView.AnimationOptions = reduceMotion() ? .effectFade : [.slideDown, .effectFade]
                table.beginUpdates(); table.insertRows(at: inserted, withAnimation: motion); table.endUpdates()
                lastInsertion = motion
            } else if let inserted {
                // Further down, the article being read does not move: rows above it go in at once and the list is put back where it
                // was; rows from it down fade in.
                ids = nextIDs
                let anchor = topID.flatMap { nextIDs.firstIndex(of: $0) } ?? 0
                let above = inserted.filteredIndexSet { $0 < anchor }, rest = inserted.subtracting(above)
                table.insertRows(at: above, withAnimation: [])
                if let scroll {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: anchor).minY + topOffset))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                table.insertRows(at: rest, withAnimation: .effectFade)
                lastInsertion = rest.isEmpty ? [] : .effectFade
            } else if idsChanged {
                ids = nextIDs; table.reloadData()
            } else {
                let range = table.rows(in: table.visibleRect)
                if range.location != NSNotFound { table.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<min(ids.count, range.location + range.length)), columnIndexes: IndexSet(integer: 0)) }
            }
            if idsChanged || selectionChanged || table.selectedRow < 0 {
                if let id = parent.selection, let row = ids.firstIndex(of: id) {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    if selectionChanged { table.scrollRowToVisible(row) }
                } else { table.deselectAll(nil) }
            }
            if idsChanged && inserted == nil && (!selectionChanged || firstLoad), let top = firstLoad ? parent.initialTop : topID ?? parent.initialTop,
               let row = ids.firstIndex(of: top), let scroll {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: row).minY + (firstLoad ? parent.initialTopOffset : topOffset)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            priorSelection = parent.selection
            table.focusWhenAttached = parent.focus
            if parent.focus && !priorFocus { table.window?.makeFirstResponder(table) }
            priorFocus = parent.focus
            synchronizing = false
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.ids.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SoftRow() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.ids.indices.contains(row), let article = parent.article(parent.ids[row]) else { return nil }
            let cell = tableView.makeView(withIdentifier: .init("article"), owner: self) as? Cell ?? Cell()
            cell.configure(article, feed: parent.feedTitle(article), iconURL: parent.iconURL(article), loader: parent.imageLoader)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let table, parent.ids.indices.contains(table.selectedRow) else { return }
            let id = parent.ids[table.selectedRow]
            if id != parent.selection { ReaderPerformance.selectionStarted(id); parent.selection = id }
        }
        func recordTop() {
            guard !synchronizing, let table else { return }
            let row = table.rows(in: table.visibleRect).location
            if ids.indices.contains(row) {
                parent.onTop(ids[row])
                parent.onTopOffset?(ids[row], Double((scroll?.contentView.bounds.minY ?? 0) - table.rect(ofRow: row).minY))
            }
        }
    }

    @MainActor final class Cell: NSTableCellView {
        // Labels are part of the row, so clicks and context menus belong to the table.
        override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
        private let source = NSTextField(labelWithString: "")
        private let title = NSTextField(wrappingLabelWithString: "")
        private let summary = NSTextField(wrappingLabelWithString: "")
        private let timestamp = NSTextField(labelWithString: "")
        let favicon = NSImageView()
        let thumbnail = NSImageView()
        private var representedID: UUID?
        private var iconURL: URL?
        private var thumbnailURL: URL?
        private var imageTasks: [Task<Void, Never>] = []
        private var isRead = false
        override var backgroundStyle: NSView.BackgroundStyle { didSet { updatePalette() } }
        deinit { imageTasks.forEach { $0.cancel() } }
        override init(frame: NSRect) {
            super.init(frame: frame)
            identifier = .init("article")
            source.font = .systemFont(ofSize: 10); source.textColor = .secondaryLabelColor
            source.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 2; title.lineBreakMode = .byWordWrapping
            title.cell?.truncatesLastVisibleLine = true
            summary.font = .systemFont(ofSize: 11); summary.textColor = .secondaryLabelColor
            summary.maximumNumberOfLines = 2; summary.lineBreakMode = .byWordWrapping
            summary.cell?.truncatesLastVisibleLine = true
            summary.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            timestamp.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            timestamp.alignment = .right
            timestamp.setAccessibilityLabel(String(localized: "Article Publication Date", bundle: ReaderLocalization.bundle))
            timestamp.setContentCompressionResistancePriority(.required, for: .horizontal)
            timestamp.setContentHuggingPriority(.required, for: .horizontal)
            source.setContentHuggingPriority(.defaultLow, for: .horizontal)
            source.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let header = NSStackView(views: [favicon, source, timestamp])
            header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 8
            header.distribution = .fill
            let text = NSStackView(views: [title, summary])
            text.orientation = .vertical; text.alignment = .leading; text.spacing = NativeArticleList.Metrics.textGap
            let body = NSStackView(views: [text, thumbnail])
            body.orientation = .horizontal; body.alignment = .top; body.spacing = 8
            body.distribution = .fill
            let stack = NSStackView(views: [header, body])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = NativeArticleList.Metrics.headerGap
            stack.translatesAutoresizingMaskIntoConstraints = false
            favicon.imageScaling = .scaleProportionallyUpOrDown; thumbnail.imageScaling = .scaleProportionallyUpOrDown
            favicon.setAccessibilityLabel(String(localized: "Subscription Icon", bundle: ReaderLocalization.bundle)); thumbnail.setAccessibilityLabel(String(localized: "Article Thumbnail", bundle: ReaderLocalization.bundle))
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: NativeArticleList.Metrics.topInset),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -NativeArticleList.Metrics.bottomInset),
                header.widthAnchor.constraint(equalTo: stack.widthAnchor), body.widthAnchor.constraint(equalTo: stack.widthAnchor),
                body.heightAnchor.constraint(equalToConstant: NativeArticleList.Metrics.bodyHeight),
                text.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor),
                favicon.widthAnchor.constraint(equalToConstant: 18), favicon.heightAnchor.constraint(equalToConstant: 18),
                thumbnail.widthAnchor.constraint(equalToConstant: 52), thumbnail.heightAnchor.constraint(equalToConstant: 52),
                title.widthAnchor.constraint(equalTo: text.widthAnchor), summary.widthAnchor.constraint(equalTo: text.widthAnchor)
            ])
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ article: Article, feed: String, iconURL: URL? = nil, loader: ReaderImageLoader? = nil) {
            isRead = article.isRead
            source.stringValue = (article.starredAt == nil ? "" : "★ ") + feed
            title.stringValue = article.displayTitle; title.font = .systemFont(ofSize: 14, weight: article.isRead ? .medium : .semibold)
            summary.stringValue = article.summary
            let published = article.publishedAt
            if published == .distantPast {
                timestamp.stringValue = "—"; timestamp.toolTip = String(localized: "Publication date unknown", bundle: ReaderLocalization.bundle)
            } else {
                var style: Date.FormatStyle = .dateTime.hour().minute()
                if !Calendar.current.isDateInToday(published) { style = style.month().day() }
                if !Calendar.current.isDate(published, equalTo: .now, toGranularity: .year) { style = style.year() }
                timestamp.stringValue = published.formatted(style)
                timestamp.toolTip = String(localized: "Published: \(published.formatted(.dateTime.year().month().day().hour().minute().second().timeZone()))", bundle: ReaderLocalization.bundle)
            }
            updatePalette()
            let imageURL = article.imageURL.flatMap { ArticleURL.validated($0) }
            guard representedID != article.id || self.iconURL != iconURL || thumbnailURL != imageURL else { return }
            imageTasks.forEach { $0.cancel() }; imageTasks = []
            representedID = article.id; self.iconURL = iconURL; thumbnailURL = imageURL
            favicon.image = nil; thumbnail.image = nil; thumbnail.isHidden = imageURL == nil
            let id = article.id
            guard let loader else { return }
            for (url, isThumbnail) in [(iconURL, false), (imageURL, true)] {
                guard let url else { continue }
                imageTasks.append(Task { [weak self] in
                    guard let data = try? await loader.image(url: url, at: .now), !Task.isCancelled else { return }
                    self?.completeImage(NSImage(data: data), articleID: id, url: url, thumbnail: isThumbnail)
                })
            }
        }
        private func updatePalette() {
            let selected = backgroundStyle == .emphasized
            let isRead = isRead && backgroundStyle != .raised            // a row that is selected quietly is read at full strength
            // The unread mark is the colour of the source name itself (soft accent), and it turns gray like the title once the article is read.
            // A plain string with `textColor` keeps `lineBreakMode` (a long name ends with an ellipsis); an attributed string without a
            // paragraph style lost it, and the name was clipped without one.
            source.textColor = selected ? .alternateSelectedControlTextColor : self.isRead ? .secondaryLabelColor : AppPalette.accent   // the real read state, not the quiet-selection one
            title.textColor = selected ? .alternateSelectedControlTextColor : isRead ? .secondaryLabelColor : .labelColor
            summary.textColor = selected ? .alternateSelectedControlTextColor : isRead ? .tertiaryLabelColor : .secondaryLabelColor
            timestamp.textColor = selected ? .alternateSelectedControlTextColor : isRead ? .tertiaryLabelColor : .secondaryLabelColor
            favicon.alphaValue = isRead && !selected ? 0.75 : 1
            thumbnail.alphaValue = favicon.alphaValue
        }
        func completeImage(_ image: NSImage?, articleID: UUID, url: URL, thumbnail: Bool) {
            guard representedID == articleID, (thumbnail ? thumbnailURL : iconURL) == url else { return }
            (thumbnail ? self.thumbnail : favicon).image = image
        }
    }
}
