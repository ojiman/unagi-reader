import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ReaderCore

private typealias LibraryScope = ReaderWorkspaceScope

struct ReaderView: View {
    @Bindable var store: ReaderStore
    @Bindable var refresh: FeedRefreshController
    let imageLoader: ReaderImageLoader
    @State private var scope: LibraryScope? = .all
    @State private var workspace = ReaderWorkspaceState()
    @State private var selection: UUID?
    @State private var pageForward = true
    @State private var scrollMemory = ReaderScrollMemory()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The panel's width when the app started (the ideal width of the inspector). The width while the person drags is kept in `NotePanelWidthMemory`.
    @State private var startingPanelWidth = NotePanelWidth.load()
    /// The window's width, for the most the note panel may take. It is read only by `NoteInspectorColumn`, so a window resize does not redraw the reader.
    @State private var windowSpace = WindowSpace()
    /// True for one turn after the person dragged the panel shut, so that it is shown again (see `noteOpenBinding`).
    @State private var panelReopening = false
    @State private var saveError: String?
    @State private var noteActionMessage: String?
    /// How 「記事をノートに送る」 reaches the note's editor (specification 3.3).
    @State private var noteLink = NoteEditorLink()
    @State private var loading: ArticleLoadingController
    private var displayedContent: ArticleContent? { loading.displayed }
    /// Set while the "add subscription" sheet is open: the folder the new subscription goes to.
    @State private var addingTo: SubscriptionTarget?
    @State private var removingFeed: Feed?
    @State private var renamingFolder: String?
    /// The subscription whose name is being edited in its sidebar row (decision 0043).
    @State private var renaming: SidebarRenaming?
    @State private var folderExpansion = FolderExpansion()
    /// The subscription whose 「フォルダへ移動…」 chooser is open.
    @State private var movingFeedID: UUID?
    @State private var folderName = ""
    /// How far the original page has slid out to the right while it closes (decision 0044), the width of its column, and whether it is closing.
    @State private var originalSlide: CGFloat = 0
    @State private var originalColumnWidth: CGFloat = 600
    @State private var originalClosing = false
    @State private var opml: OPMLImportFlow
    @State private var originalPage = OriginalPageState()
    @State private var restoreListFocus = true
    private let notePasteboard: NSPasteboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocused: Bool
    /// The list filter's field is shown (`/` or the magnifier). Its text is `workspace.listFilter`.
    @State private var filterPresented = false
    @State private var translation: TranslationController

    init(store: ReaderStore, refresh: FeedRefreshController, imageLoader: ReaderImageLoader,
         initialScope: ReaderWorkspaceScope = .all, initialNoteOpen: Bool = false, initialListShown: Bool = false, initialListFilter: String = "",
         translationEngine: TranslationEngine = .system,
         notePasteboard: NSPasteboard = .general,
         chooseOPML: @escaping @MainActor () async -> URL? = OPMLFilePanel.chooseFile) {
        self.store = store; self.refresh = refresh
        self.notePasteboard = notePasteboard
        _opml = State(initialValue: OPMLImportFlow(store: store, refresh: refresh, chooseFile: chooseOPML))
        self.imageLoader = imageLoader
        _loading = State(initialValue: ArticleLoadingController(store: store))
        _scope = State(initialValue: initialScope)
        var initialWorkspace = ReaderWorkspaceState()
        initialWorkspace.scope = initialScope
        initialWorkspace.noteOpen = initialNoteOpen
        initialWorkspace.noteListShown = initialListShown
        initialWorkspace.listFilter = initialListFilter
        _translation = State(initialValue: TranslationController(engine: translationEngine))
        _columnVisibility = State(initialValue: SidebarFold.folded(pageOpen: false, noteOpen: initialNoteOpen) ? .doubleColumn : .all)
        _workspace = State(initialValue: initialWorkspace)
    }

    private var selectedExpiry: Date? {
        guard let article = selectedArticle, article.contentDeletedAt == nil else { return nil }
        return RetentionPolicy(days: store.retentionDays).expiresAt(receivedAt: article.firstReceivedAt, firstReadAt: article.firstReadAt)
    }
    func copyNote() -> Bool {
        guard let note = store.note, !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let item = NSPasteboardItem()
        guard item.setString(note.text, forType: .string) else {
            saveError = String(localized: "The note could not be copied to the clipboard.", bundle: ReaderLocalization.bundle)
            return false
        }
        notePasteboard.clearContents()
        guard notePasteboard.writeObjects([item]) else {
            saveError = String(localized: "The note could not be copied to the clipboard.", bundle: ReaderLocalization.bundle)
            return false
        }
        noteActionMessage = String(localized: "Note copied", bundle: ReaderLocalization.bundle)
        return true
    }

    private var selectedArticle: Article? { selection.flatMap { store.article(id: $0) } }
    /// The articles of the scope, narrowed by the list filter (specification 3.1.4).
    private var visibleArticleIDs: [UUID] { store.filteredIDs(scopeArticleIDs, matching: workspace.listFilter) }
    private var scopeArticleIDs: [UUID] {
        switch scope ?? .all {
        case .folder(let name): store.folderArticleIDs(folder: name, keeping: selection)
        case .all: store.visibleArticleIDs(feedID: nil, unreadOnly: false, keeping: selection)
        case .starred: store.starredArticleIDs(keeping: selection)
        case .unread: store.visibleArticleIDs(feedID: nil, unreadOnly: true, keeping: selection)
        case .feed(let id): store.visibleArticleIDs(feedID: id, unreadOnly: false, keeping: selection)
        }
    }

    private var scopeTitle: String {
        switch scope ?? .all {
        case .folder(let name): name
        case .all: String(localized: "All Articles", bundle: ReaderLocalization.bundle)
        case .unread: String(localized: "Unread", bundle: ReaderLocalization.bundle)
        case .starred: String(localized: "Star", bundle: ReaderLocalization.bundle)
        case .feed(let id): store.feed(id: id)?.displayTitle ?? String(localized: "Article", bundle: ReaderLocalization.bundle)
        }
    }

    var body: some View {
        // The library window's own chain is long (the CI compiler gives up on a longer one); the OPML import is added from outside it.
        windowContent
            .modifier(OPMLImportPresentation(flow: opml, store: store))
            .modifier(RenameOnReturn(begin: beginRenamingSelection))
            // `Esc` from the article, the list or the note's editor closes the note, also while the original page is open beside it (decision 0050).
            // The original page has its own `Esc` (`closeOriginal`), and a field of the page keeps it.
            .onExitCommand {
                if ReaderShortcutPolicy.escapeClosesNote(noteOpen: noteOpen, keyboardInOriginalPage: ReaderKeyboardCommands.isInOriginalPage(NSApp.keyWindow?.firstResponder)) { closeNote() }
            }
            .focusedSceneValue(\.readerActions, readerActions)
            .task {
                if ReadingBenchmark.requested { await ReadingBenchmark.run(store: store, refresh: refresh) }
                else if MotionBenchmark.requested { await MotionBenchmark.run(benchmarkActions) }
            }
            .modifier(ArticleTranslationPresentation(controller: translation, articleID: selection, title: selectedArticle?.title,
                content: displayedContent, keysEnabled: shortcutsEnabled, readerShown: originalPage.url == nil))
            .onKeyPress("/") { guard shortcutsEnabled else { return .ignored }; filterPresented = true; return .handled }
            .onKeyPress("c") { guard shortcutsEnabled, originalPage.url == nil else { return .ignored }; sendToNote(); return .handled }

    }

    private var windowContent: some View {
        reader
        .onChange(of: scope) { old, new in
            if let old {
                scrollMemory.state.select(selection)
                workspace.rememberReader(scrollMemory.state, in: old)
            }
            workspace.scope = new ?? .all
            enterScope()
            // The sidebar stays folded while the original page is open, also when the person goes to another screen (decision 0046).
            withAnimation(reduceMotion ? nil : .easeOut(duration: SidebarFold.motionDuration)) {
                columnVisibility = targetColumns(pageOpen: originalPage.url != nil)
            }
        }
    }

    private var reader: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 280)
        } content: {
            articleList.id(scope).background(AppPalette.surfaceColor).navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 640)
                .background(ListColumnCollapse(collapsed: SidebarFold.listFolded(noteOpen: noteOpen, listShown: workspace.noteListShown), animated: !reduceMotion, space: windowSpace))
        } detail: {
            originalColumn.frame(minWidth: NotePanelWidth.articleMinimum)
                .overlay(alignment: .top) { articleBand.ignoresSafeArea(.container, edges: .top) }
                // The width goes on the panel's content. Put on the inspector itself it had no effect, and the panel stayed about 270 pt wide.
                .inspector(isPresented: noteOpenBinding) {
                    NoteInspectorColumn(space: windowSpace, startingWidth: startingPanelWidth) { limit in notePanel(limit: limit) }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onGeometryChange(for: Double.self, of: { Double($0.size.width) }) { windowSpace.width = $0 }
        .tint(AppPalette.accentColor)
        .containerBackground(AppPalette.surfaceColor, for: .window)
        .task(id: selectedExpiry) {
            guard let expiry = selectedExpiry else { return }
            do {
                if expiry > .now { try await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow)) }
                try Task.checkCancellation()
                perform { try store.purgeExpired(at: .now) }
            } catch { /* Selection changes cancel the old article's deadline. */ }
        }
        .task { try? await imageLoader.prepare(at: .now) }
        .onChange(of: store.contentRevision) { _, _ in
            loading.refreshCachedContent()
        }
        .onChange(of: selection) { _, id in
            // The page slides out to the right (the way it came in, reversed) and shows the next article's reader text.
            if originalPage.closesWhenSelecting(id) { dismissOriginal { listFocused = true } }
            scrollMemory.state.select(id)
        }
        .task(id: selection) {
            if let id = selection { await loading.load(articleID: id) }
            else { loading.clear() }
        }
        .onKeyPress("j") { guard noteOpen, shortcutsEnabled else { return .ignored }; move(1); return .handled }   // from the reader or the panel; the list has its own
        .onKeyPress("k") { guard noteOpen, shortcutsEnabled else { return .ignored }; move(-1); return .handled }
        .onKeyPress("m") {
            guard shortcutsEnabled, let article = selectedArticle else { return .ignored }
            perform { try store.setRead(article, !article.isRead) }; return .handled
        }
        .onKeyPress("b") { guard shortcutsEnabled else { return .ignored }; openExternal(); return .handled }
        .onKeyPress("s") { guard shortcutsEnabled else { return .ignored }; perform(.toggleStar); return .handled }
        .onKeyPress("v") { guard shortcutsEnabled else { return .ignored }; openOriginal(); return .handled }
        .onKeyPress("n") { guard shortcutsEnabled else { return .ignored }; toggleNote(); return .handled }
        .sheet(item: $addingTo) { target in
            SubscriptionSheet(store: store, folder: target.folder) { scope = .feed($0) }
        }
        .overlay(alignment: .bottomLeading) {
            if let noteActionMessage {
                Text(noteActionMessage).font(.callout).padding(10).background(.regularMaterial, in: .rect(cornerRadius: 8)).padding(12)
            }
        }
        .task(id: noteActionMessage) {
            guard noteActionMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            noteActionMessage = nil
        }
        .alert(String(localized: "Could Not Save", bundle: ReaderLocalization.bundle), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(String(localized: "Close", bundle: ReaderLocalization.bundle)) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .alert(String(localized: "Rename Folder", bundle: ReaderLocalization.bundle), isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField(String(localized: "Folder Name", bundle: ReaderLocalization.bundle), text: $folderName.singleLine())
            Button(String(localized: "Save", bundle: ReaderLocalization.bundle)) {
                guard let old = renamingFolder else { return }
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                perform {
                    try store.renameFolder(from: old, to: name)
                    folderExpansion.rename(from: old, to: name)
                    if scope == .folder(old) {
                        let next: LibraryScope = name.isEmpty ? .all : .folder(name)
                        workspace.rememberReader(scrollMemory.state, in: next); scope = next
                    }
                }
                renamingFolder = nil
            }
            Button(String(localized: "Cancel", bundle: ReaderLocalization.bundle), role: .cancel) { renamingFolder = nil }
        } message: { Text(String(localized: "An existing name merges the folders. An empty name moves subscriptions to Unfiled.", bundle: ReaderLocalization.bundle)) }
    }

    private var sidebar: some View {
        let grouped = Dictionary(grouping: store.feeds, by: \.folder)
        let folders = grouped.keys.filter { !$0.isEmpty }.sorted()
        let list = List(selection: $scope) {
            Section(String(localized: "Feeds", bundle: ReaderLocalization.bundle)) {
                sidebarRow(String(localized: "All Articles", bundle: ReaderLocalization.bundle), symbol: "tray", count: store.articles.count).tag(LibraryScope.all)
                sidebarRow(String(localized: "Unread", bundle: ReaderLocalization.bundle), symbol: "circle.dotted", count: store.unreadCount).tag(LibraryScope.unread)
                sidebarRow(String(localized: "Star", bundle: ReaderLocalization.bundle), symbol: "star", count: store.starCount).tag(LibraryScope.starred)
            }
            Section {
                ForEach(grouped[""] ?? []) { feed in subscriptionRow(feed, folders: folders) }
                ForEach(folders, id: \.self) { folder in
                    DisclosureGroup(isExpanded: Binding(get: { folderExpansion.isExpanded(folder) }, set: { folderExpansion.set(folder, expanded: $0) })) {
                        ForEach(grouped[folder] ?? []) { feed in subscriptionRow(feed, folders: folders) }
                    } label: {
                        sidebarRow(folder, symbol: "folder", count: store.folderUnreadCount(folder: folder), addHelp: String(localized: "Add Subscription to “\(folder)”", bundle: ReaderLocalization.bundle), onAdd: { addingTo = SubscriptionTarget(folder: folder) }, onDropFeeds: { dropFeeds($0, into: folder) }).tag(LibraryScope.folder(folder))
                            .contextMenu { Button(String(localized: "Rename…", bundle: ReaderLocalization.bundle)) { folderName = folder; renamingFolder = folder } }
                    }
                }
            } header: {
                SidebarSectionHeader(title: String(localized: "Subscriptions", bundle: ReaderLocalization.bundle), help: String(localized: "Add a Subscription", bundle: ReaderLocalization.bundle), action: { addingTo = SubscriptionTarget(folder: "") }, onDropFeeds: { dropFeeds($0, into: "") })
            }
        }
        .listStyle(.sidebar)
        .onChange(of: folders) { old, new in folderExpansion.forget(Set(old).subtracting(new)) }
        // The sidebar's band belongs to the window buttons and the two buttons (decision 0057): the rows scroll below it, and so does
        // the scroll bar. The list's own frame starts under the band, as the safe area of a column reports 0 (see `ListHeader`).
        return VStack(spacing: 0) {
            Color.clear.frame(height: ListHeader.bandHeight).contentShape(Rectangle()).gesture(WindowDragGesture())
            list
        }
        .modifier(SidebarPaper())
        .navigationTitle("Unagi Reader")
        .toolbar(removing: .sidebarToggle)
        .background(SidebarTitlebarControls(refreshing: refresh.refreshing,
            visible: columnVisibility != .doubleColumn && columnVisibility != .detailOnly,
            onAdd: { addingTo = SubscriptionTarget(folder: "") }, onRefresh: { Task { await refresh.refresh() } }))
    }

    private func subscriptionRow(_ feed: Feed, folders: [String]) -> some View {
        HStack {
            SubscriptionIconView(feed: feed, loader: imageLoader)
            if let edit = inlineEdit(for: .feed(feed.id), initial: feed.title) { InlineNameField(initial: edit.initial, onFinish: edit.finish) }
            else { Text(feed.displayTitle).lineLimit(1) }
            Spacer()
            Text((store.feedUnreadCounts[feed.id] ?? 0).formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let error = refresh.errors[feed.id] {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).help(error)
                    .accessibilityLabel(String(localized: "Refresh failed: \(error)", bundle: ReaderLocalization.bundle))
            }
        }.padding(.vertical, 4)
            .draggable(FeedDrag(id: feed.id))
            .tag(LibraryScope.feed(feed.id))
            .popover(isPresented: Binding(get: { movingFeedID == feed.id }, set: { if !$0 { movingFeedID = nil } }), arrowEdge: .trailing) {
                MoveToFolderView(folders: folders, current: feed.folder, onMove: { folder in movingFeedID = nil; moveFeeds([feed.id], to: folder) }, onClose: { movingFeedID = nil })
            }
            .contextMenu {
                Button(String(localized: "Refresh This Subscription", bundle: ReaderLocalization.bundle)) { Task { await refresh.refresh(feedIDs: [feed.id]) } }
                Button(String(localized: "Rename", bundle: ReaderLocalization.bundle)) { renaming = .feed(feed.id) }
                Button(String(localized: "Move to Folder…", bundle: ReaderLocalization.bundle)) { movingFeedID = feed.id }
                Button(String(localized: "Unsubscribe…", bundle: ReaderLocalization.bundle), role: .destructive) { removingFeed = feed }
            }
    }

    private func sidebarRow(_ title: String, symbol: String, count: Int, addHelp: String? = nil, onAdd: @escaping () -> Void = {}, onDropFeeds: (([UUID]) -> Bool)? = nil,
                            inlineEdit: (initial: String, finish: (String?) -> Void)? = nil) -> some View {
        SidebarRow(title: title, symbol: symbol, count: count, addHelp: addHelp, onAdd: onAdd, onDropFeeds: onDropFeeds, inlineEdit: inlineEdit)
    }

    /// What a row needs while its name is edited in place (nil for every other row).
    private func inlineEdit(for target: SidebarRenaming, initial: String) -> (initial: String, finish: (String?) -> Void)? {
        renaming == target ? (initial, { finishRename(target, typed: $0) }) : nil
    }

    /// Return on the selected subscription: edit its name in its row (the folder rows rename with a question, see 0043).
    private func beginRenamingSelection() -> Bool {
        // Only while the sidebar (an outline view) has the keyboard: Return in the article list or the note must not rename.
        guard renaming == nil, NSApp.keyWindow?.firstResponder is NSOutlineView else { return false }
        switch scope {
        case .feed(let id): renaming = .feed(id)
        default: return false
        }
        return true
    }

    /// The name was typed (nil: Esc). An empty or unchanged name saves nothing; a failure is shown, never dropped.
    private func finishRename(_ target: SidebarRenaming, typed: String?) {
        renaming = nil
        switch target {
        case .feed(let id):
            guard let feed = store.feed(id: id), let name = NameEdit.result(old: feed.title, typed: typed) else { return }
            perform { try store.updateSubscription(feed, title: name, folder: feed.folder) }
        }
    }

    /// Subscriptions dropped on a folder row (or on the sources header, which is "unfiled"). True if any of them moved.
    private func dropFeeds(_ ids: [UUID], into folder: String) -> Bool { moveFeeds(ids, to: folder) }

    /// Moves subscriptions into a folder (empty: unfiled). The rows glide to their new place and the folder opens to show them
    /// (no motion with Reduce Motion). True if any of them moved.
    @discardableResult private func moveFeeds(_ ids: [UUID], to folder: String) -> Bool {
        var moved = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            perform { moved = try store.moveFeeds(ids: ids, toFolder: folder) }
            if moved { folderExpansion.reveal(folder) }
        }
        return moved
    }

    private var articleList: some View {
        // Swift 6.3 crashes compiling an actor-isolated method reference as the setter.
        NativeArticleList(ids: visibleArticleIDs, article: { store.article(id: $0) }, feedTitle: { store.feed(id: $0.feedID)?.displayTitle ?? $0.displayPublisher },
            selection: Binding(get: { selection }, set: { selectArticle($0) }), initialTop: scrollMemory.state.listScrollAnchor, focus: listFocused && originalPage.url == nil,
            shortcutsEnabled: shortcutsEnabled, onTop: { scrollMemory.state.listScrollAnchor = $0 },
            onKey: { key in
                switch key {
                case "j": move(1)
                case "k": move(-1)
                case "m": if let article = selectedArticle { perform { try store.setRead(article, !article.isRead) } }
                case "b": openExternal()
                case "v": openOriginal()
                case "s": perform(.toggleStar)
                case "n": toggleNote()
                case "/": ReaderPerformance.motionBegan("filter-open", duration: 0.25); filterPresented = true
                case "t": toggleTranslation()
                case "c": sendToNote()
                default: break
                }
            }, imageLoader: imageLoader, iconURL: { article in
                let feed = store.feed(id: article.feedID)
                return ImageMetadata.favicon(iconURL: feed?.iconURL, siteURL: feed?.siteURL, sourceURL: feed?.sourceURL)
            }, initialTopOffset: scrollMemory.state.listScrollOffset,
            onTopOffset: { id, offset in scrollMemory.state.listScrollAnchor = id; scrollMemory.state.listScrollOffset = offset },
            headerInset: ListHeader.height)
        .focused($listFocused)
        // The list's band: its empty part moves the window (decision 0057).
        .overlay(alignment: .top) { BandDragArea().frame(height: ListHeader.bandHeight).ignoresSafeArea(.container, edges: .top) }
        .navigationTitle("")                                           // the list draws its own title (ListHeader); the system one ran out of the column
        .overlay {
            if visibleArticleIDs.isEmpty {
                ContentUnavailableView(String(localized: "No Articles", bundle: ReaderLocalization.bundle), systemImage: "tray",
                    description: Text(String(localized: "Add a subscription or choose another list.", bundle: ReaderLocalization.bundle)))
            }
        }
        .overlay(alignment: .top) {
            ListHeader(title: scopeTitle, count: visibleArticleIDs.count).ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .top) {
            // A band folds with its column (decision 0057): the folded list's view still draws, so its controls are taken away.
            // The safe area is ignored by a container that stays: the modifier on the control itself, which comes and goes with the
            // fold, made the layout loop until AppKit raised an exception in narrow windows (#222).
            Group {
                if !SidebarFold.listFolded(noteOpen: noteOpen, listShown: workspace.noteListShown) {
                    ListFilterBar(text: $workspace.listFilter, shown: filterShown,
                                  atLeftEdge: SidebarFold.folded(pageOpen: originalPage.url != nil, noteOpen: noteOpen),
                                  open: { ReaderPerformance.motionBegan("filter-open", duration: 0.25); filterPresented = true },
                                  close: { filterPresented = false; listFocused = true },
                                  dismiss: { filterPresented = false })
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .onKeyPress("j") { guard shortcutsEnabled else { return .ignored }; move(1); return .handled }
        .onKeyPress("k") { guard shortcutsEnabled else { return .ignored }; move(-1); return .handled }
    }

    /// What `--motion-benchmark` plays: the same functions the keys call (issue #212).
    private var benchmarkActions: MotionBenchmark.Actions {
        MotionBenchmark.Actions(
            selectFirst: { selectArticle(visibleArticleIDs.first) },
            next: { move(1) }, previous: { move(-1) },
            toggleNote: toggleNote, switchLayout: switchNoteLayout,
            openPage: openOriginal, closePage: closeOriginal,
            openFilter: { ReaderPerformance.motionBegan("filter-open", duration: 0.25); filterPresented = true },
            closeFilter: { ReaderPerformance.motionBegan("filter-close", duration: 0.25); filterPresented = false })
    }
    private var readerActions: ReaderActions {
        let article = selectedArticle
        return ReaderActions(noteOpen: noteOpen, toggleNote: toggleNote, starred: article?.starredAt != nil, canStar: article != nil,
                             toggleStar: { perform(.toggleStar) },
                             canSendToNote: article != nil && originalPage.url == nil, sendToNote: sendToNote,
                             canOpenBrowser: article?.originalURL.flatMap { ArticleURL.validated($0) } != nil, openBrowser: openExternal)
    }
    /// The article column's band (decision 0057). The buttons are always there and disabled when they cannot act, so nothing moves.
    private var articleBand: some View {
        let article = selectedArticle
        let translated = translation.isOn(for: article?.id)
        return ArticleBand(
            status: translation.state.key?.articleID == article?.id || translation.state.key == nil ? translation.state.state : .idle,
            translationTarget: translation.target,
            showOriginal: { translation.reset() },
            buttons: [
                BandButton(id: "note", symbol: "note.text", help: String(localized: "Open or Close Note (⌥⌘I)", bundle: ReaderLocalization.bundle),
                           label: noteOpen ? String(localized: "Close Note", bundle: ReaderLocalization.bundle) : String(localized: "Open Note", bundle: ReaderLocalization.bundle), action: toggleNote),
                BandButton(id: "star", symbol: article?.starredAt == nil ? "star" : "star.fill", help: String(localized: "Toggle Star (s)", bundle: ReaderLocalization.bundle),
                           label: article?.starredAt == nil ? String(localized: "Add Star", bundle: ReaderLocalization.bundle) : String(localized: "Remove Star", bundle: ReaderLocalization.bundle), enabled: article != nil) { perform(.toggleStar) },
                // `translate` has no filled form (specification 3.6).
                BandButton(id: "translate", symbol: translated ? "character.bubble.fill" : "character.bubble",
                           help: originalPage.url != nil ? String(localized: "Translation is unavailable while viewing the original page. Return to the article (Esc) to translate.", bundle: ReaderLocalization.bundle) : String(localized: "Translate into \(TranslationLanguages.name(translation.target)) or show original (t)", bundle: ReaderLocalization.bundle),
                           label: translated ? String(localized: "Show Original", bundle: ReaderLocalization.bundle) : String(localized: "Translate", bundle: ReaderLocalization.bundle),
                           enabled: translation.targetReady && article != nil && originalPage.url == nil && displayedContent?.articleID == article?.id, action: toggleTranslation),
                BandButton(id: "browser", symbol: "globe", help: String(localized: "Open Original Page in Browser (b)", bundle: ReaderLocalization.bundle), label: String(localized: "Open original page in browser", bundle: ReaderLocalization.bundle),
                           enabled: article?.originalURL.flatMap { ArticleURL.validated($0) } != nil, action: openExternal),
            ],
            // The sidebar and the list are folded: the note beside the article (decision 0049).
            atLeftEdge: SidebarFold.folded(pageOpen: originalPage.url != nil, noteOpen: noteOpen)
                && SidebarFold.listFolded(noteOpen: noteOpen, listShown: workspace.noteListShown),
            originalHost: originalPage.url.map { $0.host ?? $0.absoluteString }, closeOriginal: closeOriginal)
    }

    /// The note beside the reader (the inspector).
    private func notePanel(limit: Double) -> some View {
        NotePanel(store: store,
                  canPrevious: NoteArticleSwitcher.canMove(-1, from: selection, in: visibleArticleIDs),
                  canNext: NoteArticleSwitcher.canMove(1, from: selection, in: visibleArticleIDs),
                  onPrevious: { guard panelMayMove else { return }; perform(.previous) },
                  onNext: { guard panelMayMove else { return }; perform(.next) },
                  onCopy: { _ = copyNote() },
                  onClose: closeNote,
                  listShown: workspace.noteListShown, onSwitchLayout: switchNoteLayout, link: noteLink)
            .modifier(NotePanelWidthMemory(limit: limit, space: windowSpace))
    }

    /// Not while Japanese text is being composed.
    private var panelMayMove: Bool {
        !ReaderKeyboardCommands.hasMarkedText(NSApp.keyWindow?.firstResponder)
    }

    private var originalColumn: some View {
        ZStack(alignment: .trailing) {
            detail.allowsHitTesting(originalPage.url == nil).accessibilityHidden(originalPage.url != nil)
            if let url = originalPage.url, let expectedID = originalPage.articleID {
                OriginalPageView(url: url, onClose: closeOriginal, onCommand: { command in
                    guard selection == expectedID, originalPage.articleID == expectedID else { return }
                    perform(command)
                })
                    .id([expectedID.uuidString, url.absoluteString]).transition(.move(edge: .trailing))
                    .offset(x: originalSlide)
                    .padding(.top, ArticleBand.compactHeight)              // right below the article band, which holds its ✕ and host name
                    .ignoresSafeArea(.container, edges: .top)              // the title bar's safe area would add to the gap (#204)
            }
        }.clipped()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { originalColumnWidth = $0 }
    }

    @ViewBuilder private var detail: some View {
        if let article = selectedArticle {
            ArticleDetailView(article: article, content: displayedContent?.articleID == article.id ? displayedContent : nil,
                expiry: selectedExpiry, updateAvailable: loading.availableUpdate?.articleID == article.id,
                error: loading.error, initialAnchor: scrollMemory.state.scrollAnchors[article.id], initialOffset: scrollMemory.state.scrollOffsets[article.id] ?? 0,
                onScroll: { anchor, offset in scrollMemory.state.recordScroll(articleID: article.id, anchor: anchor, offset: offset) },
                onInteraction: { loading.recordInteraction(articleID: article.id) },
                onUpdate: { perform { try loading.applyAvailableUpdate() } },
                onDisplayBegin: { guard selection == article.id else { return }; ReaderPerformance.displayBegan(article.id) },
                onDisplayed: { guard ReaderKeyboardCommands.acceptsDisplay(articleID: article.id, selectedID: selection, contentID: displayedContent?.articleID, originalVisible: originalPage.url != nil) else { return }; perform { try store.markDisplayed(articleID: article.id, at: .now) } }, imageLoader: imageLoader, pageForward: pageForward, pageMotion: originalPage.url == nil,
                translated: translation.shown(for: article.id))
        } else {
            VStack(spacing: 18) {
                Image(systemName: "book.pages").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(AppPalette.accentColor.opacity(0.8))
                Text(verbatim: "Read with room to think.").font(.system(size: 24, weight: .medium, design: .serif))
                Text(String(localized: "Choose an article from the list.", bundle: ReaderLocalization.bundle))
                    .font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.surfaceColor)
        }
    }

    /// The filter's field stays while it has text, also across scopes (specification 3.1.4).
    private var filterShown: Bool { filterPresented || !workspace.listFilter.isEmpty }
    private var shortcutsEnabled: Bool { ReaderKeyboardCommands.permits(sheet: addingTo != nil || renaming != nil || renamingFolder != nil || movingFeedID != nil, originalPage: originalPage.url != nil) }
    private func openExternal() {
        guard let string = selectedArticle?.originalURL, let url = ArticleURL.validated(string) else { return }
        if !NSWorkspace.shared.open(url) { saveError = String(localized: "The browser could not be opened.", bundle: ReaderLocalization.bundle) }
    }
    private func openOriginal() {
        guard originalPage.url == nil, let article = selectedArticle, let url = article.originalURL else { return }
        restoreListFocus = ReaderKeyboardCommands.listHasFocus(declared: listFocused, responder: NSApp.keyWindow?.firstResponder)
        // The page slides in and the sidebar folds as one move (decision 0046).
        ReaderPerformance.motionBegan("page-open", duration: SidebarFold.motionDuration)
        withAnimation(reduceMotion ? nil : .easeOut(duration: SidebarFold.motionDuration)) {
            _ = originalPage.open(articleID: article.id, url: url)
            columnVisibility = targetColumns(pageOpen: true)
        }
    }
    private func closeOriginal() {
        dismissOriginal {
            scrollMemory.state.returnFromOriginal()
            listFocused = restoreListFocus
        }
    }
    /// Slides the original page out to the right, then closes it. A page that goes away without a motion would not be the reverse of
    /// how it came in. With Reduce Motion it just closes. A second request while it slides out is ignored (it closes anyway).
    private func dismissOriginal(then done: @escaping () -> Void) {
        guard originalPage.url != nil, !originalClosing else { return }
        guard !reduceMotion else { originalPage.close(); columnVisibility = targetColumns(pageOpen: false); done(); return }
        originalClosing = true
        ReaderPerformance.motionBegan("page-close", duration: SidebarFold.motionDuration)
        // The page slides out and the sidebar comes back as one move, however the page was closed (decision 0046).
        withAnimation(.easeOut(duration: SidebarFold.motionDuration)) {
            originalSlide = originalColumnWidth
            columnVisibility = targetColumns(pageOpen: false)
        } completion: {
            originalPage.close()
            originalSlide = 0
            originalClosing = false
            done()
        }
    }

    private func perform(_ command: ReaderCommand) {
        guard addingTo == nil, renaming == nil, NSApp.keyWindow?.attachedSheet == nil else { return }
        switch command {
        case .next: move(1)
        case .previous: move(-1)
        case .toggleStar:
            guard let article = selectedArticle else { return }
            perform { try store.setStar(articleID: article.id, isStarred: article.starredAt == nil, at: .now) }
        case .closeOriginal: closeOriginal()
        case .toggleNote: toggleNote()
        }
    }

    private var noteOpen: Bool { workspace.noteOpen }
    private var noteOpenBinding: Binding<Bool> {
        // The panel is closed only by the note button, ⌥⌘I, the ✕ or `Esc` (`toggleNote`). Dragging its edge shut also reports `false` here. The note
        // stays open, and the panel is shown again on the next turn: ignoring the report left the panel gone while the app still counted it as
        // open, and the person could lose the panel with no way back that they would find.
        Binding(get: { noteOpen && !panelReopening }, set: { open in
            if open { workspace.noteOpen = true }
            else if noteOpen { panelReopening = true; Task { @MainActor in panelReopening = false } }
        })
    }
    /// Opens or closes the note beside the article: the sidebar and the list fold away to the left and the note comes in from the right, as
    /// one move (decision 0049), the same as the original page. The list is folded by `ListColumnCollapse`, in the same time.
    private func toggleNote() {
        ReaderPerformance.motionBegan(noteOpen ? "note-close" : "note-open", duration: SidebarFold.motionDuration)
        withAnimation(reduceMotion ? nil : .easeOut(duration: SidebarFold.motionDuration)) {
            workspace.noteOpen.toggle()
            columnVisibility = targetColumns(pageOpen: originalPage.url != nil)
        }
    }
    /// The note's ✕ and `Esc`: close the note, the same move as opening it in reverse (decision 0050).
    private func closeNote() {
        guard noteOpen else { return }
        toggleNote()
        // The list takes the keyboard, as after the original page. If the editor had it, the focus state may still say the list has it;
        // a change from false to true is what moves it (seen in CI on macOS 26.6).
        listFocused = false
        Task { @MainActor in listFocused = true }
    }
    /// 「記事をノートに送る」 (specification 3.3): the article's link, or the text selected in it as a quotation, into the note. A closed note
    /// opens first and takes the text at its end. The keyboard does not go into the note. Not from the original page.
    private func sendToNote() {
        guard originalPage.url == nil, let article = selectedArticle else { return }
        let selected = translation.isOn(for: article.id) ? nil : ArticleTextView.selectedText(in: NSApp.keyWindow)
        let url = article.originalURL.flatMap { ArticleURL.link($0) }?.absoluteString
        guard let text = NoteClip.text(title: article.displayTitle, url: url, selection: selected) else { return }
        if noteOpen, noteLink.insert(text) != .noEditor { return }
        if !noteOpen { toggleNote() }
        noteLink.insertWhenShown(text)
    }
    private func toggleTranslation() {
        guard originalPage.url == nil, let article = selectedArticle, let content = displayedContent, content.articleID == article.id else { return }
        translation.toggle(title: article.title, content: content)
    }
    /// The layout button: shows or hides the list beside the open note.
    private func switchNoteLayout() {
        ReaderPerformance.motionBegan("note-layout", duration: SidebarFold.motionDuration)
        withAnimation(reduceMotion ? nil : .easeOut(duration: SidebarFold.motionDuration)) { workspace.switchNoteLayout() }
    }
    /// The columns to show: the sidebar is folded while the original page or the note is open (decisions 0046 and 0049).
    private func targetColumns(pageOpen: Bool) -> NavigationSplitViewVisibility {
        SidebarFold.folded(pageOpen: pageOpen, noteOpen: noteOpen) ? .doubleColumn : .all
    }
    private func enterScope() {
        let restored = workspace.reader(in: workspace.scope)
        scrollMemory.state = restored; selectArticle(restored.selectedArticleID)
        listFocused = true
    }

    private func move(_ offset: Int) {
        let next = ReaderNavigation.move(selection, by: offset, in: visibleArticleIDs)
        if let next, next != selection { ReaderPerformance.selectionStarted(next); ReaderPerformance.motionBegan("article-move", duration: 0.22) }
        selectArticle(next)
    }
    private func selectArticle(_ id: UUID?) {
        pageForward = ReaderNavigation.isForward(from: selection, to: id, in: visibleArticleIDs)
        selection = id
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { saveError = error.localizedDescription }
    }
}
