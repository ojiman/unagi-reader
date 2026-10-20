# Architecture

How Unagi Reader is built, and the technical contracts a change must keep. What the person sees is in the [specification](specification.md); why a choice was made is in the [decision records](decisions/README.md); how agents work on the code is in [AGENTS.md](../AGENTS.md). Sizes, colours and timings live in the code constants named here, not in this file.

## 1. Parts

| Part | Built with |
|---|---|
| Window | SwiftUI `NavigationSplitView` (sidebar, list, reading area) with the note as an `.inspector` of the reading area |
| Article list | AppKit `NSTableView` (`NativeArticleList`, sizes in `NativeArticleList.Metrics`) |
| Article text | AppKit `NSTextView` (`NativeArticleText`) |
| Original page | `WKWebView` (`OriginalPageView`), shown when `OriginalPaintBridge` reports its first contentful paint (`OriginalPageReveal`) |
| Note editor | AppKit `NSTextView` in an `NSViewRepresentable` (`NoteTextEditor`); SwiftUI's `TextEditor` cannot set display attributes |
| Core | `Sources/ReaderCore`: SwiftData models, `ReaderStore`, feed parsing (`XMLParser`), retention. No UI |
| Network | `URLSession` on the Mac. SwiftSoup 2.13.9, pinned exactly, to read the HTML in feeds (`ArticleMarkup`) |
| Store | `Application Support/UnagiReader/Reader.store`. `--data-directory <path>` and `--seed-demo` start a synthetic library; a normal start never adds demo data |

There is no backend, no account and no AI proxy. The app has no AI of its own ([decision 0049](decisions/0049-one-note-and-no-ai-of-its-own.md)); the note editor is a standard text view, so the system's Writing Tools appear on their own (`writingToolsBehavior` is not changed).

## 2. Input from the network is untrusted

- Every URL is checked for its scheme; redirects are checked before they are followed.
- The feed parser and `OPMLParser` refuse XML entity declarations (`<!ENTITY`). `OPMLParser` reads at most 5 MB, 2,000 outlines and 64 levels.
- Feed HTML is never run; `ArticleMarkup` turns RSS HTML and Atom XHTML into paragraphs, UTF-16 link ranges (HTTP(S) only) and quote depth. A link is checked again when it is clicked.
- The app never fetches an article's page for its text ([decision 0056](decisions/0056-the-feed-text-only.md)). Bodies extracted by earlier versions stay in the store with the coverage `extracted` and are shown like any body.

## 3. Store

`ReaderStore.schema` has six models: `Feed`, `Article`, `ContentSnapshot`, `FeedMembership`, `ReaderSettings`, `Note`.

- An article's identity, first-received and first-read times, Star and memberships are kept apart from its body (`ContentSnapshot`, which expires). `FeedMembership` joins one article to several subscriptions, so counts are not doubled.
- `Feed.folder` is a one-level string; there is no folder model, so an empty folder cannot exist.
- `Article.starredAt` non-nil means starred; starring again uses the current time; there is no history of Star changes.
- `Note` has `text`, created and updated times. There is exactly one: `ReaderStore.note`. `saveNote(text:at:)` saves the text exactly as typed, with no length limit; with no note it throws `missingNote`. When the store opens, `keepOnlyOneNote(at:)` keeps the most recently edited note (ties: the lower ID), deletes the others, or creates an empty one; a failed save fails the open.
- Note models use their own main-actor `ModelContext` on the same container. Each edit is still saved synchronously; saving the note does not scan the article and membership models registered in the library context. `reload()` fetches notes through the note context.
- A save in the library context walks every model registered in it (about 8 ms for one change with 10,000 articles, #249). The read mark (`markDisplayed`) is therefore saved through a new small `ModelContext` that fetches only that article; the library context then fetches the article again by ID, which gives its instance the saved values without notifying it, so the store's `readRevision` changes and the views that show read state read it. The library context never holds an unsaved change.
- A merge (`merge`) assigns a value only when it differs from the model's, and inserts only a feed that is in no context yet: SwiftData counts an assignment of the same value, and an insert of a fetched model, as a change, and the save writes every changed model (#303).
- A refresh batch (`applyRefreshes`) is written the same way: one small `ModelContext` per batch, in an autorelease pool, fetches the articles its entries update and their bodies with one fetch each, merges the batch's feeds, saves once, and the library context then refetches the batch's feeds, changed articles and new memberships with one fetch each, for the publication. `EntryIndex` holds IDs, not models. A subscription's icon address is passed to its row as a value, because the refetch does not notify the feed. Adding a subscription (`importFeed`) still writes in the library context and reloads.
- Data compatibility follows [decision 0003](decisions/0003-beta-data-compatibility.md): none promised between betas; from 1.0, preserved and checked in CI ([specification 7.1](specification.md)). An unreadable store is never deleted or recreated by the app.
- Opt-in upgrade tests open synthetic stores made by older builds: `V1StoreUpgradeTests` (`UNAGI_READER_V1_FIXTURE_DIR`, made by `scripts/prepare-v1-store-fixture.sh`), `PreNoteStoreUpgradeTests` (`UNAGI_READER_PRE0019_FIXTURE_DIR`, commit `52429b4`), `OneNoteStoreUpgradeTests` (`UNAGI_READER_PRE0049_FIXTURE_DIR`, commit `60da7df`; [record](verification/0049-one-note-store.md)). Opening an old store drops the tables of removed models; CoreData logs this as `error:`, which is harmless.

### 3.1 Save failure and recovery

- After a failed save, `ReaderStore.rollback()` rolls back both contexts and swaps in fresh library and note `ModelContext`s on the same container. Values from the failed context are never shown.
- `needsReload` blocks every change until `reloadIfNeeded()` succeeds. A new mutating method calls `reloadIfNeeded()` first and resolves models by ID, not by a reference taken before the failure.
- One operation is never committed in part, and a failed change is never reported as done. Every change path (read, subscription, Star, note, retention) has a save-failure and reload-failure test; a new path gets one too.

### 3.2 Indexes and late results

- `ReaderStore` keeps indexes of articles, subscriptions, unread, Star and folders; lists hold ID arrays, not all models.
- A refresh applies fetched feeds in batches (#131): `FeedRefreshController.batchSize` feeds (one since #303, so each feed is one main-actor turn), or what came in within its `batchDelay` (0.5 s; tests pass a long one so batches do not depend on timing), or what is left when the last fetch ends. Each batch saves once, then publishes its changed articles and new memberships to the ordered lists, unread counts, folders and search cache. `EntryIndex` is created only for a modified feed and reused between batches; every full reload invalidates it. All-304 batches save fetch metadata without rebuilding entry or list indexes. Full reload remains the path for other operations and recovery. A failed batch save is rolled back and applied feed by feed, so only a feed that cannot be saved shows an error; a publication failure reports the saved feeds' errors and reloads committed state. The first-refresh measurements and their limits are in the [refresh index record](verification/refresh-indexes.md).
- A late fetch or render is checked against the article ID and a generation number, so it never changes another article or its read state. After the person acts, the same article's body is not replaced on its own.
- Translation (`ArticleTranslation`, ReaderCore; `TranslationController` and `TranslationHost` in the app) follows the same rule. A press gives a job with a generation; the app runs it with the system's session, which exists only inside a view's `translationTask`. The task's configuration is kept across a reset, and a new job for the same language pair invalidates it: a new configuration equal to the old one, after nil, did not run the task again (#372). A press, a reset or a changed body drops the answers of an older job. Results stay in memory only (a small cache keyed by article, body and target) and are never written to the store. `TranslationTarget` matches the Mac's global preferred languages by language and script; `articleTranslationTarget` in `UserDefaults` stores a manual choice (empty means Match System). The app reads the global language list rather than the per-app UI override. A changed target resets the controller before new work; removed manual targets remain selected and produce the unsupported-pair status.

### 3.3 Retention

- `purgeExpired(at:)` (`ContentRetention`) runs at launch, on return to the app and every 30 minutes. Expired or deleted bodies and images do not come back when a feed is received again. Changing the period checks both the old and the new limit.
- Content removal resolves articles through the ID index and fetches only snapshots whose article IDs were requested. The deletion preview, which every purge runs, fetches only the snapshots of expired or deleted articles (#250). A deletion marker does not skip cleanup of any leftover summary, image or snapshot.
- `ContentSnapshot.bodyFormatData` (optional JSON) holds the link and quote layout; it is used only when it matches the saved text, else the plain text is shown. Deleting a body deletes its snapshot and format.

## 4. Screen contracts

### 4.1 Layout and motion

- `SidebarFold` (ReaderCore, pure) decides the columns: `folded(pageOpen:noteOpen:)` for the sidebar, `listFolded(noteOpen:listShown:)` for the list. Every fold, return and slide is one `withAnimation` of `SidebarFold.motionDuration`; with Reduce Motion nothing moves.
- `NavigationSplitView` cannot fold its middle column, so `ListColumnCollapse` folds it with SwiftUI width constraints. An animatable fraction scales both the content width and the column limits to zero; the folded content is clipped and takes neither pointer input nor accessibility focus. Normal folds never change AppKit `isCollapsed`: that made AppKit enlarge the window while the leaving note still needed room (#371). The AppKit probe remembers the visible list width and restores the divider position when the other columns leave enough room. `NativeArticleList.ScrollView` fits its table to the viewport after a zero-width fold, so the old table width cannot clip returning rows.
- `ListColumnCollapse` animates the fold only in a window of 1,400 pt or more (`SidebarFold.animatesListFold`). Narrower, the fold and the return are immediate: the animated move ended the app in an `NSException` from the window's constraint pass (#222). Found by pressing the layout button and closing and opening the note in the packaged app at about 1,150 and 1,240 pt; the app's `--motion-benchmark` (10 each) ended normally with the animation off. A margin of room for the columns did not help.
- The window may restore an old native collapsed list column from its saved state (after the app ended without quitting while the note was open). `ListColumnCollapse` repairs that state and disables native collapsing (#195); subsequent folds use the SwiftUI width constraints.
- The note panel's width has an upper limit from the window, `NotePanelWidth.maximum(windowWidth:listWidth:)`: the article keeps 360 pt, the list the width it has beside the note (at least 280 pt, 400 pt at first; also while it is folded, so that its return never squeezes the article) and 80 pt of margin. `NoteInspectorColumn` applies it as the inspector's `max`, reading the window width and the list's width from `WindowSpace`, a small observable that only this column and `ListColumnCollapse` use (a resize does not redraw `ReaderView`; the list's own view reports its width, deferred, because a change inside the layout pass looped). `ListColumnCollapse` restores the remembered list width only when it and the other columns' minimum or fitting widths fit in the split view. A width at the limit is the window's, not the person's: `NotePanelWidthMemory` does not save it, so the saved width survives a small window.
- Where the keyboard goes when the note or the page opens and closes is in [specification 3.1.3](specification.md#313-changing-the-layout). A fold moves it to the article only when no editor is typing. The note's request to take it (`NoteEditorLink.focusWhenShown`) has a number; a close (`cancelFocus`) or a newer request makes an older queued callback do nothing (#322).
- Hosted tests that fold columns run one after another under `SplitViewFoldTests`.
- `OriginalPageState.selectionChanged` closes the original page when another article is chosen; keys and clicks share one selection path.
- `ReaderView.selectArticle` reads cached text synchronously through `ArticleLoadingController` before publishing a changed selection. A separate selection task would first lay out an unavailable-body document, then the saved text (#249). Selecting the same article does not reload it or discard its interaction state; a read mark still waits for the body to draw.
- Moving to the next or previous article animates the reading view's layer (`CAAnimationGroup`); the direction comes from the list order. It does not play for a body update of the same article.
- `NativeArticleList` inserts rows (`insertRows`) only when `ListInsertion.insertedIndexes` says the new order is the old order with rows put in, and the selection did not change; any other change reloads and keeps the visible article in place. At the top of the list the rows slide in (a fade with Reduce Motion). Further down, rows above the visible article go in without motion and the scroll position is restored; the rest fade in.

- The window has no title bar and no system toolbar (`.windowStyle(.hiddenTitleBar)`; decision 0057). Each column draws its own band (`bandLayout()`: the controls on the window buttons' line, `BandDragArea` behind): `ArticleBand` (status and `BandButton`s) over the article column, `ListFilterBar` (the magnifier or the search field) in the list's band (taken away while the list is folded), `NotePanel`'s band (it ignores the top safe area, as the inspector keeps one), `BandDragArea` (a `WindowDragGesture`) on empty band space. A SwiftUI `.toolbar` must not come back: the system toolbar lies over the bands and takes their clicks. The menu bar holds the band's actions (`ReaderMenuCommands`, `TranslationCommands`).

- The sidebar and the persistent article/page container ignore the top safe area once and reserve their own bands. `ListHeader` owns the compact heading size and list inset; the sidebar headings and `ArticleTextView`'s publisher share its type size. The publisher stays in the native text document, so selection, copying and scrolling keep their existing paths. It does not scale with the body. The article starts below its band without adding the native text view's old top padding.

- Motions are measured with `--performance-output <file>`: `MotionMeter` records each named motion's frames with the window's display link (`motions` in the file), and `--motion-benchmark` plays every motion ten times and quits. The baseline is in [verification/motion-baseline.md](verification/motion-baseline.md).

- Reading budgets use `--reading-benchmark --performance-output <file>` and a fresh copy of the exported `BenchmarkFixtureTests` library. The app refuses automation without an explicit data directory and the fixture's `.reading-benchmark` marker. It sends 100 `j` / `k` events through AppKit, types 64 committed characters in the note, then refreshes 100 feeds through `FeedClient` with in-memory HTTP responses (100 existing articles per feed, no network). Setup and note-opening motion are outside the W2 phases; the final refresh layout is inside. Normal startup still runs; the fixture has no feed URLs until refresh setup. `ReaderPerformance` records the process's kernel start time to the first visible table draw (`launchMilliseconds`), display-start samples and the 20 ms heartbeat's delays over 100 ms, with counts and gaps per phase. A missing launch value, missing phase, or false `readingBenchmarkComplete` is not a pass. The replay does not sample motion frame times.

### 4.2 The note panel

- `NotePanel` is the inspector. Its width is set by `inspectorColumnWidth` on the panel's content (on the inspector itself it has no effect). `NotePanelWidth` holds the range, the default and the saved value in `UserDefaults`, clamped on save and load. The key changed with decision 0050 (`notePanelWidth.0050`); loading removes the old `notePanelWidth`, so an earlier width is dropped once.
- `NotePanelWidthMemory` measures with `onGeometryChange` and saves once the width has been still for 0.6 s. The width is not `ReaderView` state: that redrew the whole window on every drag frame and froze it.
- `ReaderWorkspaceState.noteOpen` and `noteListShown` live in memory only. `toggleNote` changes `noteOpen` and the column visibility in one animation; the note's ✕ calls it too. The layout button calls `switchNoteLayout`, which does nothing while the note is closed. Dragging the edge shut reopens the panel on the next turn (`noteOpenBinding`).
- `NoteTextEditor` styles headings and list markers through `NoteLineStyle.runs(in:baseOffset:)` (ReaderCore, pure) and `NoteEditorStyle`. It changes display attributes only, in `NSTextStorageDelegate.didProcessEditing` for the edited paragraphs, never the text. It does nothing while `hasMarkedText()` is true. Paste and drop take plain text only; smart quotes, dashes, replacement and link detection are off. `textDidChange` saves once per change.
- 「Markdownをコピー」 (`ReaderView.copyNote`) writes the shown editor text, including an edit whose save failed, as one `NSPasteboardItem` string; without an editor it uses the saved note. The copy button follows the shown text's empty state through `NoteEditorLink`. A pasteboard failure shows an error. `LegacyHandoffFolder` deletes the `Handoffs` folder that older builds made (a link is removed, not followed).

### 4.3 Keys

- The list filter: `ReaderStore.filteredIDs(_:matching:)` narrows the scope's IDs with `ArticleFilter`, through `searchTexts`, a cache of folded title and summary that is not observed and is dropped on each reload (typing does not make the view watch every article; 10,000 articles: about 50 ms for the first keystroke and 17 ms after, debug build). `ListFilterField` wraps `NSSearchField` and hands its text on only when its editor has no marked text.

- `ReaderKeyboardCommands` treats only an editable `NSTextView` or `NSTextField` as typing. Single-letter keys do not act while typing, while composing with an input method, or while a sheet is open.
- `Esc` closes the note through `onExitCommand` on the window content (`ReaderShortcutPolicy.escapeClosesNote`), also while the original page is open, unless the keyboard is inside the page, which has its own `Esc`. The note's editor passes `cancelOperation:` up instead of opening its completion list; while composing it only ends the composition.
- In the original page, keys come from a separate `WKContentWorld`; they are checked for a real key press, an input element, an input method, modifier keys and the current article.

### 4.4 Colours and the window

- `AppPalette` holds every colour. The reading surface is one fixed value (`surface`) for the list, the article, the note and the window; `textBackgroundColor` is not used because it turns vibrant inside split view columns. The toolbar background is hidden.
- `SoftRow` draws the list selection with `isEmphasized` always false (no system blue). The accent is a calm orange with light and dark values.

### 4.5 Images and icons

- One actor fetches, checks, scales (ImageIO) and caches images and subscription icons off the main actor. The same scheme and redirect checks apply. No third-party favicon service gets the subscription URLs.
- Limits: response 4 MiB, 20,000,000 pixels before decoding, longest side 1,200 px after scaling; disk cache 64 MiB; success kept 7 days, failure 10 minutes; 4 fetches at a time.
- Each result is checked for the ID, the URL and cancellation. A late image never changes a row height, the selection or the reading position: image frames are fixed, and hosted views in the text have a fixed frame.
- Image choice: enclosure, media, then images in the body. `hatena:imageurl` (checked by namespace) and HTML `entry-image` come first; images in `cite`, favicons, bookmark counters and images marked small are skipped.

### 4.6 UI language

`ReaderLocalization.bundle` holds the English-source catalog in ReaderCore. App-owned text uses `String(localized:bundle:)`; user content stays verbatim. Missing source titles and publishers stay empty in storage, with localized fallbacks only at presentation. Existing saved strings are not matched against translated placeholders or rewritten. English is the development language. `AppLanguage` reads only the app domain's `AppleLanguages`; an absent key means Match System. Choosing a language writes that same native key, and Match System removes it. The resource bundle and main app declare the same languages, so macOS chooses the localization at launch. The app does not change its locale or rebuild its menus while running. The article target reads the global preferences independently (3.2).

The package build plugin compiles the catalog with Xcode's `xcstringstool`, including on native SwiftPM, which otherwise only copies it. The app build copies the resulting resource bundle into `Contents/Resources` and declares its languages in `CFBundleLocalizations`. `test-build-app.sh` checks the packaged keys and the ZIP/signature round-trip. Label-based tests use a volatile English argument domain; the real-app smoke harness sets the native English preference only for its dedicated synthetic app and removes that key on exit.

## 5. Build and CI

The toolchains, the CI jobs and when each one runs are in [AGENTS.md](../AGENTS.md#commands). The build and test contracts:

- CI builds on macOS 26.6 (the build floor); the support floor macOS 27.0 is checked only on the local Mac ([decision 0007](decisions/0007-support-floor-macos-27.md)). Do not use APIs that need the macOS 27 SDK.
- Real-app UI smoke tests use a separate XCUITest target in `UITests/UISmoke.xcodeproj`, driven by `scripts/run-ui-smoke.sh`. The job `ui-smoke` runs them on pushes to `main` and manual runs with the `release` job's app, not for pull requests and outside `check`; a failed, partial or skipped suite fails that job only. The app itself stays a Swift package.
- `release` makes an ad hoc signed app and checks the signature after a ZIP round trip. There is no Developer ID signing, notarization or automatic release.
