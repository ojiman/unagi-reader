import AppKit
import SwiftUI
import Testing
import ReaderCore
@testable import UnagiReader

// Checks PRD-11 (specification 7).
@Suite(EnglishLanguage()) @MainActor struct NativeArticleListTests {
    @Test func theTableFitsTheViewportAfterAZeroWidthFold() {
        let scroll = NativeArticleList.ScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let table = NativeArticleList.Table(frame: scroll.bounds)
        NativeArticleList.configure(table)
        scroll.documentView = table
        for width in [400.0, 0.0, 280.0, 400.0, 0.0, 280.0] {
            scroll.setFrameSize(NSSize(width: width, height: 500))
            scroll.tile()
            if width > 0 { #expect(table.frame.width <= scroll.contentSize.width + 1, "table \(table.frame.width), viewport \(scroll.contentSize.width)") }
        }
    }

    @Test func selectedFolderListReceivesKeyboardFocusAfterMount() {
        var selection: UUID?
        let parent = NativeArticleList(ids: [], article: { _ in nil }, feedTitle: { _ in "" }, selection: Binding(get: { selection }, set: { selection = $0 }), initialTop: nil, focus: true, shortcutsEnabled: true, onTop: { _ in }, onKey: { _ in })
        let table = NativeArticleList.Table(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
        table.addTableColumn(NSTableColumn(identifier: .init("article")))
        let coordinator = NativeArticleList.Coordinator(parent); coordinator.table = table
        coordinator.update(parent)
        let window = NSWindow(contentRect: table.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(table)
        #expect(window.firstResponder === table)
    }
    /// A letter that is not a shortcut must not move the selection: the table's type-to-select jumped to a row whose text starts with it
    /// (the owner's recording of `F`, issue #226).
    @Test func aLetterThatIsNotAShortcutDoesNotMoveTheSelection() {
        let table = NativeArticleList.Table(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
        #expect(!table.allowsTypeSelect)
    }
    private func labels(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
    }
    @Test func publicationTimeIsSeparateFromSourceAndNeverUsesReceiptTime() throws {
        let cell = NativeArticleList.Cell()
        let article = Article(feedID: UUID(), title: "合成記事", summary: "要約", publisher: "合成", publishedAt: .now, receivedAt: .now.addingTimeInterval(-3600))
        cell.configure(article, feed: "合成購読")
        let time = try #require(labels(in: cell).first { $0.toolTip?.hasPrefix("Published: ") == true })
        let expected = article.publishedAt.formatted(.dateTime.hour().minute())
        #expect(time.stringValue == expected)
        #expect(labels(in: cell).contains { $0.stringValue == "合成購読" })
        article.publishedAt = .now.addingTimeInterval(-86400 * 400)
        cell.configure(article, feed: "合成購読")
        #expect(time.stringValue == article.publishedAt.formatted(.dateTime.year().month().day().hour().minute()))
        article.publishedAt = .distantPast
        cell.configure(article, feed: "合成購読")
        #expect(time.stringValue == "—" && time.toolTip == "Publication date unknown")
    }
    @Test func readPaletteAndSelectionResetWhenCellIsReused() throws {
        let cell = NativeArticleList.Cell()
        let article = Article(feedID: UUID(), title: "合成記事", summary: "合成要約", publisher: "合成", publishedAt: .now)
        cell.configure(article, feed: "合成購読")
        let title = try #require(labels(in: cell).first { $0.stringValue == article.title })
        let summary = try #require(labels(in: cell).first { $0.stringValue == article.summary })
        let unreadTitle = title.textColor, unreadSummary = summary.textColor
        article.isRead = true
        cell.configure(article, feed: "合成購読")
        #expect(title.textColor != unreadTitle && summary.textColor != unreadSummary)
        #expect(cell.thumbnail.alphaValue < 1 && cell.favicon.alphaValue < 1)
        cell.backgroundStyle = .emphasized
        #expect(title.textColor == .alternateSelectedControlTextColor && cell.thumbnail.alphaValue == 1)
        cell.backgroundStyle = .normal
        article.isRead = false
        cell.configure(article, feed: "合成購読")
        #expect(title.textColor == unreadTitle && summary.textColor == unreadSummary)
        #expect(cell.thumbnail.alphaValue == 1 && cell.favicon.alphaValue == 1)
    }
    @Test(arguments: [280.0, 400.0, 640.0]) func articleTextUsesSpaceUpToCompactThumbnail(width: Double) throws {
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: width, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事の長いタイトルを途中で短く切らずに表示します。", summary: "合成の長い要約です。幅が狭くてもタイトルや次の記事と重ならず、広げると読める範囲が増えます。", publisher: "合成", publishedAt: .now)
        article.imageURL = "https://synthetic.example/image.png"
        cell.configure(article, feed: "合成購読")
        cell.layoutSubtreeIfNeeded()
        let thumbnail = cell.convert(cell.thumbnail.bounds, from: cell.thumbnail)
        #expect(abs(thumbnail.maxX - (cell.bounds.width - 12)) < 1)
        #expect(thumbnail.width == 52)
        let time = try #require(labels(in: cell).first { $0.toolTip?.hasPrefix("Published: ") == true })
        let title = try #require(labels(in: cell).first { $0.stringValue == article.title })
        let timeRect = cell.convert(time.bounds, from: time)
        let titleRect = cell.convert(title.bounds, from: title)
        if width < 640 { #expect(titleRect.height > 25) }
        let summary = try #require(labels(in: cell).first { $0.stringValue == article.summary })
        let summaryRect = cell.convert(summary.bounds, from: summary)
        #expect(abs(timeRect.maxX - thumbnail.maxX) <= 2)
        #expect(abs(titleRect.maxX + 8 - thumbnail.minX) <= 2)
        #expect(cell.isFlipped ? timeRect.maxY <= thumbnail.minY : timeRect.minY >= thumbnail.maxY)
        #expect(summaryRect.minY >= 8 && summaryRect.maxY <= NativeArticleList.Metrics.rowHeight - 8)
        #expect(cell.isFlipped ? titleRect.maxY <= summaryRect.minY : titleRect.minY >= summaryRect.maxY)
        article.imageURL = nil
        cell.configure(article, feed: "合成購読"); cell.layoutSubtreeIfNeeded()
        #expect(cell.thumbnail.isHidden)
        #expect(abs(cell.convert(title.bounds, from: title).maxX - (width - 12)) <= 2)
    }
    @Test func theHeadlineLeadsAndTheSourceNameAndSummaryAreQuieter() throws {
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 400, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事", summary: "合成の要約です。", publisher: "合成", publishedAt: .now)
        cell.configure(article, feed: "合成購読")
        let source = try #require(labels(in: cell).first { $0.stringValue.hasSuffix("合成購読") })
        let title = try #require(labels(in: cell).first { $0.stringValue == article.title })
        let summary = try #require(labels(in: cell).first { $0.stringValue == article.summary })
        #expect(title.font?.pointSize == 14)                                                   // the headline and the favicon decide interest
        #expect(source.font?.pointSize == 10)                                                  // decision 0028: supporting information is smaller
        #expect(summary.font?.pointSize == 11)
    }
    @Test func theListSharesTheSurfaceOfTheReader() {
        let scroll = NSScrollView(), table = NativeArticleList.Table()
        NativeArticleList.applySurface(scroll: scroll, table: table)
        #expect(table.backgroundColor == AppPalette.surface)                                    // one dark for the list, the article and the note
        #expect(scroll.drawsBackground && scroll.backgroundColor == AppPalette.surface)
        for name in [NSAppearance.Name.darkAqua, .vibrantDark] {                                // the split view's columns can be vibrant: same gray
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let c = AppPalette.surface.usingColorSpace(.sRGB)!
                #expect(abs(c.redComponent * 255 - 30) < 0.5 && abs(c.greenComponent * 255 - 30) < 0.5 && abs(c.blueComponent * 255 - 30) < 0.5)
            }
        }
    }
    @Test func theSelectedRowIsAQuietGrayNotTheSystemBlue() throws {
        let row = NativeArticleList.SoftRow(frame: NSRect(x: 0, y: 0, width: 320, height: NativeArticleList.Metrics.rowHeight))
        row.isSelected = true
        row.isEmphasized = true                                                                 // the table does this when it has the keyboard focus
        #expect(!row.isEmphasized)                                                              // still drawn in the quiet way, with the normal text colours
        #expect(row.interiorBackgroundStyle == .raised)                                         // "selected, quietly": the cell shows its full-strength text
        row.isSelected = false
        #expect(row.interiorBackgroundStyle == .normal)
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let c = AppPalette.selection.usingColorSpace(.sRGB)!
                #expect(c.alphaComponent > 0.05 && c.alphaComponent < 0.25)
                #expect(abs(c.redComponent - c.greenComponent) < 0.01 && abs(c.greenComponent - c.blueComponent) < 0.01)   // neutral, no hue
            }
        }
    }
    @Test func aSelectedReadRowIsNotDimmed() throws {
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 320, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事", summary: "合成要約", publisher: "合成", publishedAt: .now)
        article.isRead = true
        cell.configure(article, feed: "合成購読")
        let title = try #require(labels(in: cell).first { $0.stringValue == article.title })
        let summary = try #require(labels(in: cell).first { $0.stringValue == article.summary })
        #expect(title.textColor == .secondaryLabelColor && summary.textColor == .tertiaryLabelColor)   // read: dimmed
        cell.backgroundStyle = .raised                                                          // selected in the quiet way
        #expect(title.textColor == .labelColor && summary.textColor == .secondaryLabelColor)   // the selected row is easy to read
        cell.backgroundStyle = .normal
        #expect(title.textColor == .secondaryLabelColor)
    }
    @Test func theUnreadSourceNameCarriesTheAccentAndTurnsGrayWhenRead() throws {
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 320, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事", summary: "要約", publisher: "合成", publishedAt: .now)
        cell.configure(article, feed: "合成購読")
        let source = try #require(labels(in: cell).first { $0.stringValue.hasSuffix("合成購読") })
        #expect(source.stringValue == "合成購読")                                               // no dot: the colour is the mark
        #expect(source.textColor == AppPalette.accent)                                          // unread
        article.isRead = true
        cell.configure(article, feed: "合成購読")
        #expect(source.textColor == .secondaryLabelColor)                                       // read: gray, like the read headline
        cell.backgroundStyle = .raised                                                          // read and selected quietly
        #expect(source.textColor == .secondaryLabelColor)
        cell.backgroundStyle = .normal
        article.isRead = false
        cell.configure(article, feed: "合成購読")
        cell.backgroundStyle = .emphasized
        #expect(source.textColor == .alternateSelectedControlTextColor)
    }
    @Test func aLongSourceNameEndsWithAnEllipsisInsteadOfBeingClipped() throws {
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 252, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事", summary: "要約", publisher: "合成", publishedAt: .now)
        for read in [false, true] {
            article.isRead = read
            cell.configure(article, feed: "はてなブックマーク - 人気エントリー - テクノロジー")
            cell.layoutSubtreeIfNeeded()
            let source = try #require(labels(in: cell).first { $0.stringValue.hasSuffix("テクノロジー") })
            // What is drawn comes from the attributed string. Without a truncating paragraph style it wraps at a space and clips
            // without an ellipsis ("はてなブックマー", "Latest"), whatever lineBreakMode says.
            let style = source.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(source.lineBreakMode == .byTruncatingTail)
            #expect(style?.lineBreakMode == .byTruncatingTail)
            #expect(cell.convert(source.bounds, from: source).height < 20)                     // one line, so the header keeps its height
        }
    }
    @Test func rowsHaveRoomToBreathe() throws {
        #expect(NativeArticleList.Metrics.rowHeight == 108)                                    // decision 0026: 96 felt cramped
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 400, height: NativeArticleList.Metrics.rowHeight))
        let article = Article(feedID: UUID(), title: "合成記事の長いタイトルを二行に折り返して表示します。二行目まで使います。", summary: "合成の要約です。", publisher: "合成", publishedAt: .now)
        article.imageURL = "https://synthetic.example/image.png"
        cell.configure(article, feed: "合成購読")
        cell.layoutSubtreeIfNeeded()
        func rect(_ view: NSView) -> NSRect { cell.convert(view.bounds, from: view) }
        func gap(_ a: NSRect, _ b: NSRect) -> CGFloat { max(b.minY - a.maxY, a.minY - b.maxY) }
        let source = try #require(labels(in: cell).first { $0.stringValue.hasSuffix("合成購読") })
        let title = try #require(labels(in: cell).first { $0.stringValue == article.title })
        let summary = try #require(labels(in: cell).first { $0.stringValue == article.summary })
        let height = cell.bounds.height
        let top = cell.isFlipped ? rect(source).minY : height - rect(source).maxY
        let titleTop = cell.isFlipped ? rect(title).minY : height - rect(title).maxY
        #expect(top >= 14)                                                                      // space above the first line
        #expect(gap(rect(source), rect(title)) >= 5.5 && titleTop > top)                       // between the source line and the title
        #expect(gap(rect(title), rect(summary)) >= 3.5)                                         // between the title and the summary
        let bottom = cell.isFlipped ? height - rect(summary).maxY : rect(summary).minY
        #expect(bottom >= 14)                                                                   // space below the last line
    }
    @Test func lateImagesNeverLeakAcrossReusedRows() {
        let first = Article(feedID: UUID(), title: "A", summary: "", publisher: "合成", publishedAt: .now)
        let second = Article(feedID: UUID(), title: "B", summary: "", publisher: "合成", publishedAt: .now)
        let a = URL(string: "https://synthetic.example/a.png")!, b = URL(string: "https://synthetic.example/b.png")!
        first.imageURL = a.absoluteString; second.imageURL = b.absoluteString
        let cell = NativeArticleList.Cell(frame: NSRect(x: 0, y: 0, width: 320, height: NativeArticleList.Metrics.rowHeight))
        cell.configure(first, feed: "合成", iconURL: a, loader: nil)
        cell.configure(second, feed: "合成", iconURL: b, loader: nil)
        let stale = NSImage(size: NSSize(width: 10, height: 10))
        cell.completeImage(stale, articleID: first.id, url: a, thumbnail: true)
        cell.completeImage(stale, articleID: first.id, url: a, thumbnail: false)
        #expect(cell.thumbnail.image == nil && cell.favicon.image == nil)
        let current = NSImage(size: NSSize(width: 20, height: 20))
        cell.completeImage(current, articleID: second.id, url: b, thumbnail: true)
        cell.completeImage(current, articleID: second.id, url: b, thumbnail: false)
        #expect(cell.thumbnail.image === current && cell.favicon.image === current)
        #expect(cell.frame.height == NativeArticleList.Metrics.rowHeight)
        cell.configure(second, feed: "合成", iconURL: b, loader: nil)
        #expect(cell.thumbnail.image === current)
    }
    @Test func starKeyRoutesWithoutConsumingModifiedInput() throws {
        let table = NativeArticleList.Table()
        var handled: [String] = []
        table.keyHandler = { handled.append($0); return true }
        for flags: NSEvent.ModifierFlags in [[], .shift, .command] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1))
            table.keyDown(with: event)
        }
        #expect(handled == ["s"])
    }
    /// Decision 0049: `n` no longer sends a summary and the picker key `t` is long gone, so neither reaches the reader (a new meaning for
    /// `n`, opening the note, comes in a later change).
    @Test func theNoteAndTranslateKeysRouteAndModifiedKeysDoNot() throws {
        let table = NativeArticleList.Table()
        var handled: [String] = []
        table.keyHandler = { handled.append($0); return true }
        func press(_ key: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
            table.keyDown(with: event)
        }
        try press("t", keyCode: 17)
        try press("n", keyCode: 45)
        try press("n", keyCode: 45, flags: .command)
        #expect(handled == ["t", "n"])                                              // `t` translates (3.6), `n` opens the note; ⌘N does nothing here
    }
    @Test func backgroundInsertionAndReorderPreserveSelectedArticleAndTopOffset() {
        let original = (0..<40).map { _ in UUID() }
        let articles = Dictionary(uniqueKeysWithValues: original.map { id in
            let article = Article(feedID: UUID(), title: "合成", summary: "要約", publisher: "合成", publishedAt: .now)
            article.id = id; return (id, article)
        })
        var selected: UUID? = original[10]
        func parent(_ ids: [UUID]) -> NativeArticleList {
            NativeArticleList(ids: ids, article: { articles[$0] }, feedTitle: { _ in "" },
                selection: Binding(get: { selected }, set: { selected = $0 }), initialTop: nil,
                focus: false, shortcutsEnabled: true, onTop: { _ in }, onKey: { _ in })
        }
        let coordinator = NativeArticleList.Coordinator(parent(original))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
        let table = NativeArticleList.Table(frame: NSRect(x: 0, y: 0, width: 280, height: 4000))
        table.headerView = nil; table.rowHeight = NativeArticleList.Metrics.rowHeight; table.intercellSpacing = .zero
        table.addTableColumn(NSTableColumn(identifier: .init("article")))
        table.dataSource = coordinator; table.delegate = coordinator; scroll.documentView = table
        coordinator.table = table; coordinator.scroll = scroll
        coordinator.update(parent(original))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 8).minY + 17))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(table.rows(in: table.visibleRect).location == 8)
        #expect(abs(scroll.contentView.bounds.minY - table.rect(ofRow: 8).minY - 17) < 1)
        let inserted = [UUID()] + original
        var reordered = inserted
        reordered.swapAt(9, 20)
        for ids in [inserted, reordered] {
            coordinator.update(parent(ids))
            #expect(table.selectedRow == ids.firstIndex(of: original[10]))
            #expect(selected == original[10])
            let top = table.rows(in: table.visibleRect).location
            #expect(ids[top] == original[8])
            #expect(abs(scroll.contentView.bounds.minY - table.rect(ofRow: top).minY - 17) < 1)
            let article = articles[original[8]]!
            let url = URL(string: "https://synthetic.example/delayed.png")!
            article.imageURL = url.absoluteString
            if let cell = table.view(atColumn: 0, row: top, makeIfNecessary: true) as? NativeArticleList.Cell {
                cell.configure(article, feed: "合成", iconURL: url, loader: nil)
                let offset = scroll.contentView.bounds.minY
                cell.completeImage(NSImage(size: NSSize(width: 400, height: 400)), articleID: article.id, url: url, thumbnail: true)
                cell.completeImage(NSImage(size: NSSize(width: 18, height: 18)), articleID: article.id, url: url, thumbnail: false)
                cell.layoutSubtreeIfNeeded()
                #expect(abs(scroll.contentView.bounds.minY - offset) < 1 && table.rowHeight == NativeArticleList.Metrics.rowHeight)
            } else { Issue.record("Expected the visible native cell") }
        }
    }
    @Test func remountRestoresTopOffsetIndependentlyOfSelection() {
        let ids = (0..<30).map { _ in UUID() }
        var selection: UUID? = ids[12]
        let parent = NativeArticleList(ids: ids, article: { _ in nil }, feedTitle: { _ in "" }, selection: Binding(get: { selection }, set: { selection = $0 }), initialTop: ids[8], focus: false, shortcutsEnabled: true, onTop: { _ in }, onKey: { _ in }, initialTopOffset: 17)
        let coordinator = NativeArticleList.Coordinator(parent)
        let table = NativeArticleList.Table(frame: NSRect(x: 0, y: 0, width: 280, height: 3000))
        table.headerView = nil; table.rowHeight = NativeArticleList.Metrics.rowHeight; table.intercellSpacing = .zero
        table.addTableColumn(NSTableColumn(identifier: .init("article")))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 300)); scroll.documentView = table
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table; coordinator.scroll = scroll
        coordinator.update(parent)
        #expect(table.selectedRow == 12)
        #expect(abs(scroll.contentView.bounds.minY - table.rect(ofRow: 8).minY - 17) < 1)
    }

    // MARK: New articles slide in where they land (specification 3.2, #284)

    private struct ListRig {
        let coordinator: NativeArticleList.Coordinator
        let table: NativeArticleList.Table
        let scroll: NSScrollView
        let parent: ([UUID]) -> NativeArticleList
        let selected: () -> UUID?
    }
    private func listRig(count: Int, select: Int) -> (rig: ListRig, ids: [UUID]) {
        let ids = (0..<count).map { _ in UUID() }
        var all = Dictionary(uniqueKeysWithValues: ids.map { id -> (UUID, Article) in
            let article = Article(feedID: UUID(), title: "合成", summary: "要約", publisher: "合成", publishedAt: .now)
            article.id = id; return (id, article)
        })
        var selected: UUID? = ids[select]
        func parent(_ list: [UUID]) -> NativeArticleList {
            for id in list where all[id] == nil {
                let article = Article(feedID: UUID(), title: "新着", summary: "要約", publisher: "合成", publishedAt: .now)
                article.id = id; all[id] = article
            }
            return NativeArticleList(ids: list, article: { all[$0] }, feedTitle: { _ in "" },
                selection: Binding(get: { selected }, set: { selected = $0 }), initialTop: nil,
                focus: false, shortcutsEnabled: true, onTop: { _ in }, onKey: { _ in })
        }
        let coordinator = NativeArticleList.Coordinator(parent(ids))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
        let table = NativeArticleList.Table(frame: NSRect(x: 0, y: 0, width: 280, height: 4000))
        table.headerView = nil; table.rowHeight = 96; table.intercellSpacing = .zero
        table.addTableColumn(NSTableColumn(identifier: .init("article")))
        table.dataSource = coordinator; table.delegate = coordinator; scroll.documentView = table
        coordinator.table = table; coordinator.scroll = scroll
        coordinator.reduceMotion = { false }
        coordinator.update(parent(ids))
        scroll.contentView.scroll(to: .zero)                                                   // showing the selected row scrolled the list: start at the top
        scroll.reflectScrolledClipView(scroll.contentView)
        return (ListRig(coordinator: coordinator, table: table, scroll: scroll, parent: parent, selected: { selected }), ids)
    }

    private let slide: NSTableView.AnimationOptions = [.slideDown, .effectFade]

    @Test func newArticlesAtTheTopSlideInAndTheListStaysAtTheTop() {
        let (rig, ids) = listRig(count: 40, select: 10)
        let added = [UUID(), UUID()]
        rig.coordinator.update(rig.parent(added + ids))
        #expect(rig.coordinator.lastInsertion == slide)
        #expect(rig.table.numberOfRows == 42)
        #expect(rig.scroll.contentView.bounds.minY == 0)                                       // still at the top: the new rows are in view
        #expect(rig.table.rows(in: rig.table.visibleRect).location == 0)
        #expect(rig.selected() == ids[10] && rig.table.selectedRow == 12)                      // the selected article is the same one
    }
    @Test func newArticlesInTheMiddleSlideInWhereTheyLand() {
        let (rig, ids) = listRig(count: 40, select: 10)
        let added = [UUID(), UUID()]
        rig.coordinator.update(rig.parent([ids[0], added[0]] + ids[1..<5] + [added[1]] + ids[5...]))
        #expect(rig.coordinator.lastInsertion == slide)
        #expect(rig.table.numberOfRows == 42 && rig.scroll.contentView.bounds.minY == 0)
        #expect(rig.selected() == ids[10] && rig.table.selectedRow == 12)
    }
    @Test func manyNewArticlesAtOnceStillSlideIn() {
        let (rig, ids) = listRig(count: 40, select: 10)
        rig.coordinator.update(rig.parent((0..<60).map { _ in UUID() } + ids))
        #expect(rig.coordinator.lastInsertion == slide)
        #expect(rig.table.numberOfRows == 100 && rig.selected() == ids[10] && rig.table.selectedRow == 70)
    }
    @Test func whenTheReaderHasScrolledDownNewArticlesDoNotMoveWhatTheyAreReading() {
        let (rig, ids) = listRig(count: 40, select: 10)
        rig.scroll.contentView.scroll(to: NSPoint(x: 0, y: rig.table.rect(ofRow: 8).minY + 17))
        rig.scroll.reflectScrolledClipView(rig.scroll.contentView)
        rig.coordinator.update(rig.parent([UUID(), UUID()] + ids[0..<9] + [UUID()] + ids[9...]))   // two above the reader, one in view
        #expect(rig.coordinator.lastInsertion == .effectFade)
        let top = rig.table.rows(in: rig.table.visibleRect).location
        #expect(top == 10)                                                                     // row 8 before, two rows added above
        #expect(abs(rig.scroll.contentView.bounds.minY - rig.table.rect(ofRow: top).minY - 17) < 1)
        #expect(rig.selected() == ids[10] && rig.table.selectedRow == 13)
    }
    @Test func reduceMotionFadesNewArticlesInWithoutSliding() {
        let (rig, ids) = listRig(count: 40, select: 10)
        rig.coordinator.reduceMotion = { true }
        rig.coordinator.update(rig.parent([UUID()] + ids))
        #expect(rig.coordinator.lastInsertion == .effectFade)
        #expect(rig.table.numberOfRows == 41 && rig.selected() == ids[10] && rig.table.selectedRow == 11)
    }
    @Test func onlyInsertionsAreAnimated() {
        let (rig, ids) = listRig(count: 40, select: 10)
        rig.coordinator.update(rig.parent(ids))                                                // no change
        #expect(rig.coordinator.lastInsertion == nil)
        rig.coordinator.update(rig.parent(Array(ids.dropFirst())))                             // an article left
        #expect(rig.coordinator.lastInsertion == nil && rig.table.numberOfRows == 39)
        rig.coordinator.update(rig.parent((0..<30).map { _ in UUID() }))                       // another list
        #expect(rig.coordinator.lastInsertion == nil && rig.table.numberOfRows == 30)
    }
    /// The list in the window starts below the band and the title block (`headerInset`), so its top is below zero. The rig above has no
    /// insets; this checks the "at the top" test where the insets are real.
    @Test func theTopOfTheListIsFoundBelowTheWindowsInsets() {
        let (rig, ids) = listRig(count: 40, select: 10)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 400), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = rig.scroll
        rig.scroll.additionalSafeAreaInsets = NSEdgeInsets(top: 60, left: 0, bottom: 0, right: 0)
        window.layoutIfNeeded()
        let top = -rig.scroll.contentView.contentInsets.top                                    // the title bar and the 60 pt above the rows
        #expect(top < -59)
        rig.scroll.contentView.scroll(to: NSPoint(x: 0, y: top)); rig.scroll.reflectScrolledClipView(rig.scroll.contentView)
        rig.coordinator.update(rig.parent([UUID()] + ids))
        #expect(rig.coordinator.lastInsertion == slide)
        #expect(abs(rig.scroll.contentView.bounds.minY - top) < 1)                             // still at the top
    }
}
