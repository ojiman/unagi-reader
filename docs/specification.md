# Unagi Reader specification (V1)

What V1 is and is not, as the person sees it. Why the product exists is in the [vision](vision.md); how it is built is in the [architecture](architecture.md); why each rule is so is in the [decision records](decisions/README.md). How to write this file: [spec-style.md](spec-style.md). What is not written here is not a requirement.

- **Approval.** The owner approved this V1 specification on 2026-10-17 with no scope changes (#144). The language settings in 3.6 and 3.7 (#154, #271, #272), revised by the owner later that day (decision 0060), are part of V1. Approving the specification is not accepting the product: that is a separate demo on a real Mac (PRD-07).
- **Status marks.** A rule that is not built yet ends with `[not built #issue]`. A rule with no mark is built.

## 1. Purpose and scope

- The value, the user and the questions to ask when in doubt are in the [vision](vision.md): read → note → understand, in one app, with no waiting.
- V1 runs on the person's own Mac. No backend, no account, no sync.
- A new library starts empty; there is no migration from the prototype ([decision 0001](decisions/0001-fresh-library-no-prototype-migration.md)).
- Data between beta versions is not guaranteed; saves and restarts within one version are. From 1.0, data is kept across updates (7.1). If the library cannot be opened, the app shows an error and never deletes or recreates it (how SwiftData behaves with an incompatible store is not verified). Beta release notes state this limit ([decision 0003](decisions/0003-beta-data-compatibility.md)).

## 2. Promises

- The screen and the keys stay smooth; focus, the reading position, Japanese input and the system's accessibility are kept.
- Whatever body text can be had is shown readably. When none can be had, the RSS summary and a link to the original page keep the reading going. The app shows the feed's text only and never promises the full text (decision 0056).
- Read is history, Star is "come back to chew on this", and the note is the one place for the person's own words. They are independent.
- Article text within the retention period and the note can be read offline. Nothing the person wrote is deleted by the app.
- The app has no AI of its own (section 5).

### 2.1 No waiting: budgets

The vision promises that reading and typing never wait. These are the budgets a change must not break. The latest recorded measurements and their limits are in the [reading budget record](verification/reading-budgets.md); measuring a budget does not mean it passed.

| ID | Budget | How it is measured |
|---|---|---|
| W1 | `j` / `k` to the start of the next article's display: 95th percentile ≤ 100 ms, maximum ≤ 200 ms | Release build, `--reading-benchmark --performance-output <file>` (`selectionMilliseconds`), the synthetic library of `BenchmarkFixtureTests` (100 subscriptions, 10,000 articles) |
| W2 | No main-thread stall over 100 ms while reading with keys, while typing in the note, or while a refresh runs | The same run: `schedulingGapsOver100ms` is empty |
| W3 | Launch to a list with articles: ≤ 1 s with the same library, on a copy of the app that has been launched before. A copy's first launch (after an install or an update) is recorded separately and has no budget | The same run, on the second or a later launch of the same copy: `launchMilliseconds`, from the kernel's process start time to the first visible list draw with rows |

## 3. Reading and the note

### 3.0 Terms

These words mean the same thing in this specification, the user guide, the decision records and the issues. "Code" is where the term lives in the code. The areas of the screen are in 3.1.1.

**Subscriptions**

| Term | Meaning | Code |
|---|---|---|
| subscription | One feed the person follows; one row in the sidebar | `Feed` |
| source name | The name of a subscription, shown in the sidebar and on each article in the list. The sidebar section's heading is **Subscriptions** | `Feed.title` |
| feed | An RSS 1.0, RSS 2.0 or Atom document; its address is `Feed.sourceURL` | `FeedParser`, `ParsedFeed` |
| folder | A one-level group of subscriptions. It exists only by name and disappears with its last subscription | `Feed.folder` |
| Unfiled | Subscriptions in no folder. Not usable as a folder name | empty `Feed.folder`, `FolderPicker` |
| scope | What the list shows: all articles, unread, Star, a folder or one subscription | `ReaderWorkspaceScope` |

**Articles and reading**

| Term | Meaning | Code |
|---|---|---|
| article | One item of a feed | `Article` |
| body | The text to read: what the feed provided (a body an earlier version extracted from the page is kept and shown the same way) | `ContentSnapshot`, `ArticleContent` |
| RSS summary | The short description the feed gives an article | `Article.summary` |
| read / unread | An article becomes read, and its first read time is saved, when its body or RSS summary is actually shown in the article area | `Article.firstReadAt`, `ReaderStore.markDisplayed` |
| Star | The mark "come back to chew on this" (3.2) | `Article.starredAt` |
| retention period (Retention) | Days the body and RSS summary are kept: 7, 30, 90 or 365 | `RetentionPolicy`, `ReaderSettings` |
| expired | A body or RSS summary past the period. It is deleted; the Star, title and URL stay | `Article.contentDeletedAt`, `ReaderStore.purgeExpired` |

**Fetching and adding**

| Term | Meaning | Code |
|---|---|---|
| refresh | Fetching the feeds again for new articles: by hand, at launch, on return, every 30 minutes | `FeedRefreshController` |
| add sheet | The sheet that adds a subscription from a URL | `SubscriptionSheet` |
| check | Fetching and parsing the URL being typed to see if it can be added | `FeedChecker`, `FeedCheckRequest` |
| feed discovery | Finding the feed a site's page announces | `FeedDiscovery` |
| OPML | The file format that carries a list of subscriptions, for import and export | `OPMLParser`, `OPMLImporter`, `OPMLImportFlow`, `OPMLWriter`, `OPMLExportFlow` |

**The note and screen parts**

| Term | Meaning | Code |
|---|---|---|
| note | The app's one Markdown note (3.3) | `Note` |
| **Copy Markdown** | Puts the note's text, unchanged, on the pasteboard (3.3) | `NotePanel`, `ReaderView.copyNote` |
| list title | The scope's name above the list, with a count only while filtering (3.1.4) | `ListHeader` |
| ✕ | The button at the top left of the right column. It closes the original page, and the note | `OriginalPageView`, `NotePanel` |
| Settings | The settings window: **General**, **Articles** and **Shortcuts** (3.7) | `ReaderSettingsView` |

**Word use**

- Say "original page" for the web page. "Original" alone (**Show Original**, **Return to Original**) is only the article's untranslated text, in translation (3.6).
- "The list" is the article list; a list in the note is a "Markdown list".
- A "subscription" is one feed the person follows; **Subscriptions** is the sidebar heading; the "source name" is the name of the subscription an article came from.
- Quote screen labels exactly, in the English source text of the String Catalog ([spec style](spec-style.md)); the other display languages translate it (3.7).

### 3.1 The screen and reading

The screen has **four areas**. Reading shows three of them side by side (sidebar, list, article); the fourth, the note, joins on the right of the article only while it is open. How the areas are arranged is a **layout**; there are four (3.1.2).

#### 3.1.1 Areas

| Area | Code | Role |
|---|---|---|
| sidebar | `ReaderView.sidebar`, `SidebarRow` | Choose what to read (Feeds, folders, subscriptions) |
| list | `NativeArticleList`, `ListHeader` | The articles of the chosen scope |
| article | `ArticleDetailView`, `NativeArticleText` | The article's body (the RSS view) |
| original page | `OriginalPageView` | The original web page in an in-app browser, in place of the article area |
| note | `ReaderView.notePanel` (inspector) | The one Markdown note (3.3) |

#### 3.1.2 Four layouts

| Layout | Areas shown | Status |
|---|---|---|
| normal | sidebar, list, article | |
| original page | list, original page. The sidebar folds; the page uses the article's and the sidebar's width | |
| note beside the article | article, note. The sidebar and the list fold | |
| note with the list | list, article, note. The sidebar folds | |

```
normal                original page (v)     note beside article   note with the list
┌────┬────┬───────┐  ┌────┬─────────┐      ┌─────────┬─────┐     ┌────┬───────┬─────┐
│side│list│article│  │list│original │      │ article │note │     │list│article│note │
│bar │    │       │  │    │  page   │      │         │     │     │    │       │     │
└────┴────┴───────┘  └────┴─────────┘      └─────────┴─────┘     └────┴───────┴─────┘
(widths are rough; the sidebar is folded away in the original page and note layouts)
```

#### 3.1.3 Changing the layout

| Action | Result | Status |
|---|---|---|
| `v` | normal → original page. The sidebar folds, the page comes in from the right, the list keeps its width and moves to the left edge | |
| `Esc`, the ✕, `j` / `k`, a click in the list | original page → normal. The page slides out to the right and the sidebar returns, whichever way it was closed. With `j` / `k` or a click, the chosen article's text appears from under the page | |
| `n`, `⌥⌘I`, the note button (in the article band) | normal → note beside the article. The sidebar and the list fold; the note comes in from the right, and its editor takes the keyboard: the caret where the person left it, at the end of a note they never placed it in (decision 0064). `n` works only when no editable field is being typed in. Opening writes nothing into the note (no summary, source or heading) | |
| the same action again | Closes the note and returns to the screen before (scope, chosen article, reading position). The note goes and the list returns at once; the sidebar slides back (decision 0070) | |
| the layout button (in the note band, beside the ✕) | note beside the article ⇄ note with the list. The chosen article, the scroll position and the note's text do not change. Two layouts only; no key | |
| `Esc`, the note's ✕ (top left of the right column, where the original page's ✕ is) | Closes the note and shows the same article in the normal layout, with the list selection on it. While Japanese text is being composed, `Esc` cancels the composition first | |
| `Esc` with the original page and the note both open (the note opened with `n` while the page is shown) | Closes what has the keyboard: in the note, the list or the article, the note closes and the page stays; in the page, the page closes and the note stays (a field of the page keeps its own `Esc`). A second `Esc` closes the other | |
| `j` / `k` (focus in the article or the list) | Next / previous article with the note still open. In the note editor they type letters, so right after the note opens they are letters until the person clicks the article or the list | |
| `⌥⌘↑` / `⌥⌘↓`, the arrows above the note | Change only the article, with the note still open | |

- **The original page while it loads.** The page slides in at once, but its web view stays hidden behind the app's own dark surface, with a loading spinner in the middle of the column, until the page has painted its first content (or has finished loading). Then it is shown (a 0.15 s fade; none with Reduce Motion). A failed load shows its own sentence. The page itself (a white page, its own delay) is the page's business.
- **Motion.** Opening the note, switching its layout, and opening or closing the original page take about 0.3 s. Closing the note is not the reverse move: the note goes and the list returns at once, and the sidebar slides back with the system's own motion (about 0.25 s). In a window narrower than 1,400 pt the list also folds and returns at once during the other layout changes (the animated fold ended the app in an exception, #222); the sidebar, an opening note and the page keep their motion. With Reduce Motion nothing moves; the layout changes at once (decisions 0044, 0046, 0049, 0070).
- Opening or closing the note and switching its layout never change the window frame, the chosen article or the scroll position.

#### 3.1.4 Rules per area

**Bands** (decision 0057)

- The window has no system toolbar and no visible title bar. Each column has its own band at the top of the window, as high as the window buttons' band (52 pt), in the column's colour, with no line under it. A band folds with its column. No column has a second row of controls below its band.
- What each band holds, left to right:

| Column | Left | Right |
|---|---|---|
| sidebar | the window buttons | add subscription, refresh (as now) |
| list | | the filter's magnifier, which opens into the system's search field across the band (List filter, below) |
| article | the translation status as short text (3.6) | the note button, send to the note (3.3), Star, translate, globe |
| original page (in the article band, in place of the status; the band is then only as high as its controls and the page starts right below it) | ✕, the page's host name | |
| note | ✕, the layout button | previous, next, copy |

- One style: monochrome symbols of one size and one hit area; colour only for a state (a filled Star, a filled translate). No links and no accent-coloured symbols in a band.
- Dragging an empty part of a band moves the window; a double-click does what the system setting says.
- In full screen the bands stay at the top of the screen and the columns keep their places. When the pointer reveals the menu bar, the system's title bar comes down with it, over the top of the columns, with the window buttons, add subscription and refresh. The bar is the system's compact height: it fits the window buttons, and the other two sit on their line. This temporary bar uses the system appearance in light and dark themes; in Sepia its background blends with the paper colour. The green button, the system's full-screen shortcut and View ▸ Exit Full Screen leave full screen, and the window returns at its old size. If the displays change, the restored window stays accessible on a current screen.
- Every band control also has a menu bar command; the keys stay as they are (3.1.5).

**Headings**

- Feeds, **Subscriptions**, the list's current scope and the article's source name use a small 12 pt semibold heading. The top headings sit at the same visual height below the bands. When both lists are at the top, the first sidebar row and first article row's selection backgrounds start at the same height.

**Sidebar**

- Choose the scope from Feeds (all articles, unread, Star) and **Subscriptions** (folders and subscriptions). Each subscription shows its site icon. The **Subscriptions** section can be collapsed.
- Each folder stays open or closed as the person left it, also after a restart; at the first launch all are closed, and a folder made again after it disappeared starts closed.
- The rows and their scroll bar start below the sidebar's band: scrolled rows stop at its lower edge and never pass under the window buttons.
- At the top right, right-aligned: add subscription, then refresh. While a refresh runs, the refresh arrow itself turns (not with Reduce Motion) and the button stays enabled (pressing it again does nothing).
- A small orange ＋ appears at the right end of the **Subscriptions** heading on mouse-over and adds a subscription. The heading stays in place however long the list is.
- No Hide Sidebar button and no folder-management button. The sidebar shows and folds only with the layout: a drag of its edge that folds it, or brings it out while it is folded, springs back at once (#389).

**List**

- The list title is one line. It keeps the scope name visible when the sidebar folds. Counts stay in the sidebar; only a nonempty keyword filter adds its result count on the heading line. A long scope name ends with an ellipsis inside its column, leaving room for that count.
- A row: source name on the left and publication time on the right of the top line; title, summary and article image below. The title is the largest (14 pt); the summary (11 pt) and the source name and time (10 pt) are smaller, because the title and the favicon decide interest.
- The column's edge can be dragged wider.
- The reading surfaces (list, article, note) are one dark colour, with no separate grey bars or lines in the bands; only the sidebar is slightly lighter.
- One calm orange accent, only for the unread mark, the add and refresh buttons and the note's list markers. The selected row is a quiet grey, not the system blue.
- When a refresh brings new articles and the list is at the top, each new row slides in at its place in the order and pushes the rows below it down, with no limit on the number (the system's table motion, as in Mail). With Reduce Motion the new rows fade in instead. When the list is not at the top, the article being read does not move; new rows inside the visible part fade in. The selected article stays selected. Manual and automatic refreshes behave the same.
- Publication time: the time for today, date and time for earlier days, the year too for other years. An unknown time is "—"; the received time is never used instead.
- Unread: the source name in the accent colour and brighter text. Read: the whole row a calm grey. A long source name ends in "…". The selected row keeps readable contrast.

**List filter** (decision 0055)

- Only a magnifier is shown in the list's band. Clicking it or `/` grows the system's search field (as high as the band's buttons) out of it toward the left in about 0.25 s, with the cursor in it (3.1.5; no movement with Reduce Motion). While it has text the field stays open, also when the person clicks elsewhere and across scopes, and the filter applies; left empty, a click elsewhere turns it back into the magnifier and there is no filter. `Esc` in the empty field closes it and gives the list the keyboard.
- Typing narrows the list at once to the articles of the current scope (Feeds, Star, a folder, a subscription) whose title or feed summary (the text the list row shows) contains the typed text, ignoring case, accents and full-width letters. The count under the title counts the narrowed list. Clearing the field restores the list.
- Only the title and the feed summary are searched: not the article's body, not the full text the app saved, and not the note.
- The filter stays when the scope changes. It is not kept across launches.
- The chosen article stays chosen if it still matches. `j` / `k` move through the filtered list.
- While Japanese text is being composed, the list does not change.
- Typing never waits on the network or on a reload (budget W1, 2.1).
- Not built: saved filters, search of bodies or of the note, search across scopes, "mark all as read".

**Article**

- Above the title, the article's source name (3.0), the same name its list row shows, as written (the site's address only when its subscription is gone). Below the title, the weekday, date and time of publication in the system's time zone and format, for example "Friday, Oct 23, 2026 at 19:56", or "Publication date unknown". The source name scrolls with the article and keeps the same size and starting position when the article text size changes. The title is 26 pt semibold. The buttons at the top: Star and the external browser (globe). The theme and the text size are in Settings (3.7).
- Opening an article shows the feed's body (or the RSS summary) as it is; it never fetches the original page or swaps the text (RSS first, decision 0033). For more, `v` (in the app) or `b` (the browser).
- The app never takes text from the original page (decision 0056): no full-text fetch, and no line under the article that says how much text there is.
- Links and quotes of the feed's text are kept. A link opens in the default browser. Quotes look different from the text, with one bar along all the paragraphs and images of a quote; a quote inside a quote has its own bar beside it. A saved body without layout data is shown as plain text.
- The feed's HTML is shown as the feed gives it, with no handling per site (decision 0066). Images appear where the feed puts them, at their own size and never wider than the text; an image whose block has no text stands on a line of its own, and images of separate blocks on separate lines; an image taller than a line of text stands on a line of its own too, while a smaller one, such as a bookmark counter, stays in the line (an image without a size is placed when it arrives); an image in a link opens the link. When the body has images, the representative image is not shown above it. A late image never moves the text being read; a failed or offline one gives back the space kept for it, and the text being read stays. A body of images only, such as a comic, is shown as its images. Selecting, copying and **Send Article to Note** take the text without the images. A translated paragraph keeps its images at its start or end.
- Headings are larger and semibold, and stay smaller than the title. List items keep their marker ("•", "◦" inside another list, or their number) with a hanging indent per level. Code is monospaced; a code block keeps its line breaks and wraps a long line at the column. Bold and italic text keep their look; inline code has a light background. A table is one line per row with its cells at tab stops, and header cells bold. Every size follows the article text size. Copy keeps the markers, line breaks and tabs. A translated paragraph keeps its kind of block but not its bold, italic or code runs.
- The next article comes in from below, the previous from above, short and quick (following the list order). The text area does not change height when loading ends. The scroll bar shows only for an article longer than the area: moving to an article that fits shows none.
- An article becomes read when its body or RSS summary is actually shown in the article area. Scrolling the list or fetching the body does not mark it read. Receiving or showing it again does not change the first read time.

**Note**

- The rules are in 3.3. The width is kept across launches; whether the note is open is kept while the app runs.

#### 3.1.5 Keys

| Key | Action |
|---|---|
| `j` / `k` | Next / previous article |
| `s` | Star on / off |
| `n` | Open / close the note (as the note button and `⌥⌘I`), when no editable field is being typed in |
| `m` | Read / unread |
| `b` | Open the original page in the default browser |
| `v` | Open the original page in the app |
| `Esc` | Close the original page or the note and return to the same article at its reading position; with both open, the one that has the keyboard (3.1.3). While Japanese text is being composed, it cancels the composition first (decision 0050) |
| `/` | Open the list filter and put the cursor in it, when no editable field is being typed in |
| `t` | Translate the open article / show the original, when no editable field is being typed in |
| `i` | Send the article to the note (3.3), when no editable field is being typed in |
| `⌘K` | Send the article to the note (3.3) wherever the keyboard is, also in the note's editor. It is the key of Article ▸ Send Article to Note |

- `j`, `k`, `s` and `n` also work in the original page.
- In text fields (the note editor too), during input-method composition and with modifier keys, typing and the standard actions come first.
- Everything important can be done with the keyboard alone. Actions inside the external browser are out of scope.

### 3.2 Star

A **Star** is the mark "come back to chew on this". An article has a Star or not; the app saves the state and when it was given.

- `s` and the Star button change the same state.
- Starring or unstarring never changes the read time.
- Unstarring removes the article from the Star list; starring again uses a new time.
- Unstarring the chosen article keeps it shown and in place until the person moves on.
- When the body expires, the Star, title and URL stay.
- A Star never does anything to the note.
- Not built: a screen to organize Stars, a flow that makes notes from Stars (decision 0019).

### 3.3 The note, retention and deletion

The **note** is the app's **one** plain-text Markdown document ([decision 0049](decisions/0049-one-note-and-no-ai-of-its-own.md)). Opening and layout are in 3.1.2 and 3.1.3.

**Basics**

- No list of notes, no new note, no name, no folders, no delete, no undo of a delete. No goals, tags, search or nesting.
- Every change is saved; the next launch continues where the person stopped.
- The text is saved exactly as typed. A failed save is never shown as saved. Input-method composition is never disturbed.
- Nothing writes into the note unless the person types, pastes, or runs **Send Article to Note** (below): not the app, not an AI, not opening, closing or a layout change.

**Editor**

- Plain Markdown text with the system's text services, undo, Japanese input and Writing Tools (5.1).
- The panel's edge can be dragged; the width is kept across launches; dragging never folds the panel.
- Width: 640 pt at first, up to 1,280 pt, at least 300 pt. In a narrow window it leaves 360 pt for the article and 80 pt of room, and for the list the width it has beside the note (400 pt at first, at least 280 pt) also while it is folded, so that bringing the list back never squeezes the article. A saved width that the window cannot hold is shown narrower and stays saved; the first width of 640 pt therefore needs a window of about 1,480 pt. A width saved by an earlier version is dropped once, at the first launch of this version.
- Display-only styling; the saved text never changes:
  - A line that starts with one to six `#` and then a space or the line end is a heading: bold and larger.
  - A line that starts with `-`, `*`, `+` or a number (`1.`, `1)`), after at most 8 spaces, is a list item: the marker is coloured and wrapped lines align with the text.
  - Return does not continue a list; quotes and dashes are not replaced.
  - Nothing is styled during Japanese composition; it is styled after the text is confirmed or cancelled.
- Paste and drop insert plain text only.
- Not in V1: bold, italic, code, tables, check lists, a preview.

**Copy Markdown**

- In the note panel's header. Copies the note's text exactly, as UTF-8 text on the system pasteboard, the end unchanged.
- Disabled when the note is empty or only whitespace.
- The app starts no other app, makes no file and uses no network. After a copy the button's symbol is a check mark for about 1.5 s, with no motion and no dialog (VoiceOver says "Note copied"); after a failure it stays as it was and the error shows.

**Send Article to Note** ([decision 0059](decisions/0059-send-the-article-to-the-note.md))

- One command that puts the open article's source into the note. It is run by `i` or `⌘K` (3.1.5), or by Article ▸ Send Article to Note in the menu bar, which shows `⌘K`.
- The article band has a button for it, beside the note button; its help names the keys. It is off when no article is open and while the original page is shown. Clicking it does not move the keyboard.
- `⌘K` works wherever the keyboard is: in the list, in the article, in the note's editor (where a letter key would only be typed), in the filter field, and with the note closed. With the original page shown the command is off and the page keeps `⌘K`.
- With no article chosen, it does nothing.
- What it inserts, as plain text:
  - No text selected in the article: one line, `[Title](URL)`.
  - Text selected in the article: the selection with `> ` at the start of each line, then the line `> — [Title](URL)`. The selection counts wherever the keyboard is: it stays in the article, shown in grey, when the keyboard moves to the note or elsewhere. A selection that belongs to another article never counts.
  - A title with `[` or `]` gets a backslash before each. With no title the line is the URL; with no URL it is the title.
  - A title on several lines becomes one line. A URL with a space or an unbalanced parenthesis is written inside `<` and `>`. Empty lines at either end of the selection are left out.
  - With a translation shown (3.6) it inserts the line `[Title](URL)` only, never the translated text.
- Where it goes: after the note's selection or caret, where the person last left it; at the end of the note if the note was never used. A selection in the note is not replaced. The text is a paragraph of its own: an empty line separates it from text before and after it, none is added at the start of the note, and there are never two empty lines. The note's caret then sits after it, so the next one follows as another paragraph.
- The note closed: the note opens with the same motion as `n` (3.1.3), then the text is inserted at the end of the note. The article, the list selection and the reading position do not change.
- The keyboard does not move into the note, so `j` / `k` keep working. With the note open it stays where it was; when a closed note opens, the list folds away and the article takes it (with `n` the note's editor takes it).
- It is one undo step of the note's own undo.
- Where the text went is shown with the system's find indicator (a short highlight): at once when the note is open; when a closed note opens, after it has come in. VoiceOver says "Sent to note". Nothing is shown when nothing was inserted.
- While Japanese text is being composed in the note, it does nothing and the composition is not disturbed.
- A failed save is shown as with typing and never reported as done; the inserted text stays in the editor.
- The same article sent twice is inserted twice. No record, link or mark is kept about the article.
- No network and no fetch of the original page.
- Not now: inserting the whole body, a summary, a new note, sending automatically, a list of the sent articles, and running it from the original page.

**Retention and deletion**

| What | Kept | Counted from |
|---|---|---|
| article body and RSS summary | 30 days by default; 7, 30, 90 or 365 in Settings | unread: first received; read: first read. Receiving or showing again does not extend it |
| Star, title, URL | after the body expires too | — |
| the note's text | until the person deletes the characters (also after an article expires, its body is deleted, or a subscription is removed) | — |

- Shortening the period asks the person to confirm what will go.
- Nothing deletes all bodies and RSS summaries at once; the retention period removes them (decision 0061)
- An expired body or summary is deleted; the article shows that it was, and keeps the link to the original page.
- There is no way to delete the note itself.

### 3.4 Favicons and images

- A subscription's favicon and an article's image are different things.
- A subscription's icon is the one its feed names. Without one, the app reads the site's home page once and uses the icon it names (`<link rel="icon">`, or `apple-touch-icon` when there is none), else the site's `/favicon.ico`. A page that cannot be read is tried again at the next refresh; a typed feed address gets its icon at its first refresh.
- An article's image comes first from the RSS/Atom feed. For Hatena Bookmark, the article image metadata is used.
- The list and the article show an image when there is one.
- No image, a failed image or being offline never stops reading. A late image never changes a row height, the selection or the scroll position.
- Images are cached for reuse; the cache is not part of what the app promises to keep.

### 3.5 Adding and managing subscriptions

**Adding from a URL**

- A subscription is added from an RSS or Atom URL. The add sheet has only the URL field, **Cancel** and **Add** (decision 0032).
- An `http://` address is checked, and subscribed, as `https://`. An address with a port number is used as typed (decision 0040). A feed that is only on `http://` is not supported: when the `https://` form cannot be loaded, the app shows "Could not load over HTTPS. HTTP is not supported." (decision 0053).
- A site's URL works too: the app finds the feeds the page announces (`<link rel="alternate" type="application/rss+xml">` and the like), uses the first, shows its URL, and subscribes to it. A saved subscription's refresh does not do this (decision 0038).
- The URL is checked while it is typed (decision 0036):
  - About 0.8 s after typing stops (at once after a paste), the app fetches and parses it and shows one line under the field: **Checking…**, ✓ and the feed name, or why it failed.
  - **Add** is enabled only when the feed could be read (parsed as RSS 1.0, RSS 2.0 or Atom, not only a 200 answer). The checked feed is the one added.
  - While typing, a URL whose host does not look complete (`https://exa`, `https://example.c`) is not sent. Return sends names such as localhost too.
  - A URL already subscribed shows "Already subscribed: <feed name>" and is not added.
  - A failure has a short sentence per cause: 404, unreadable, server error, no network, no answer, server not found, no secure connection, http not usable, too large, a web page and not a feed, an XML error. When the only problem is control characters that XML forbids, they are removed and the feed is read.
- Direct XML input and the synthetic sample appear only when the sheet is opened with ⌥ held (for checking failures).

**The folder when adding**

- Opened from the ＋ that appears on a folder row, the sheet adds to that folder and says so in its heading, for example **Add Subscription to “Tech”**.
- Opened from the **Subscriptions** heading or the sidebar's ＋, a folder field with candidates (the same part as **Move to Folder…**) appears once the feed is read, when at least one folder exists. Paste and Return with nothing chosen adds to Unfiled (the fast path stays). Typing a name selects the closest candidate; a new name offers **Create “<name>” and Add** (decision 0037).

**Importing OPML**

- File ▸ Import OPML…. No shortcut.
- Subscriptions are added at once in one save; articles arrive afterwards. Folders are one level: deeper levels go into the top folder. Existing subscriptions are neither added again nor moved. The result is an alert (decision 0041). Its title is the result: "Subscriptions added: N", or "No new subscriptions" when nothing was added ("No subscriptions were found in this file" for an empty file). Below it, one line for each of these that is not zero, and nothing when all went well: "• Already subscribed: N" (left as they are), "• Changed to HTTPS: N" (plain `http://` addresses changed to `https://`), "• Failed: N" (addresses that could not be used). A file that cannot be read gives the title "Could not import the OPML file" and the reason below it.

**Exporting OPML**

- File ▸ Export OPML…, under the import. No shortcut. The save panel suggests `Unagi Reader Subscriptions YYYY-MM-DD.opml`.
- The file holds the subscriptions and their folders, nothing else: each folder holds its subscriptions, in the order of folder names, and the unfiled ones follow at the top level. Nothing is fetched, and there is no limit on the number of subscriptions. Importing the file into an empty library gives the same subscriptions and folders (decision 0063).
- A written file shows no message; a file that cannot be written shows "The subscriptions could not be exported" and the reason.

**Managing subscriptions**

- Right-click a subscription: refresh, rename (in the row itself), move to a folder, unsubscribe (decision 0043).
- **Unsubscribe…** asks **Unsubscribe?**, with **Unsubscribe** and **Cancel**, and the message "Articles and their content stay in the library." Cancel keeps the subscription. Confirm removes it; removing the selected subscription returns to **All Articles**.
- A subscription moved to another folder moves smoothly to its new place, and the folder opens (not with Reduce Motion).
- Two ways to move to a folder: **Move to Folder…** in the menu (a small chooser with a field: typing filters the folders; a new name offers **Create “<name>” and Move**; ↑ ↓, Return, Esc; **Unfiled** too; a folder is made by moving its first subscription into it), and drag and drop in the sidebar.
- A folder can be renamed (a name that already exists joins the two folders) and shows the articles of all its subscriptions. No empty folders and no nesting: a folder disappears with its last subscription.
- Each subscription's entries are its own articles (decision 0067). A page that two subscriptions carry, such as a social bookmark feed and the page's own site, is two articles, each with its own feed's title, date and text, and each read, starred and counted on its own. Subscribing again to an address finds the articles kept after unsubscribing.

### 3.6 Translation

A button translates the open article into another language, on the Mac, with the system's Translation framework. It uses the system session and in-memory state described in [architecture 3.2](architecture.md#32-indexes-and-late-results); the policy is in decision 0054.

**Button and key**

- A button **Translate** sits in the article band, before **Open original page in browser**. Its help names the target, for example "Translate into Japanese or show original (t)"; its icon (`character.bubble`; the system's `translate` has no filled form) is filled while a translation is shown. It is always there and is disabled when no article is open or while the target is being resolved (the toolbar does not change height).
- The same command is in the menu bar: View ▸ Translate (Return to Original while a translation is shown), without a key.
- `t` does the same, when no editable field is being typed in (3.1.5).
- Pressing it translates the title and the body of the open article, in place. Pressing it again shows the original.

**What is translated**

- Only the article's reader text (the feed's text). The note, the list and the sidebar are never translated.
- While the original page is open the button is disabled, with the help text "Translation is unavailable while viewing the original page. Return to the article (Esc) to translate.".
- Links in the translated text are plain text. The original is one press away.
- Translation is not sticky: moving to another article shows that article in its original language and stops the running translation. Nothing is translated that the person did not ask for.

**While it works and when it is done**

- The status, as short text at the left of the article band, says "Translating 3/12" (paragraphs done of all), or "Preparing languages…" while the system downloads a language pack. Title and paragraphs change from the top as results arrive. The reading position is kept. Reduce Motion: no animation.
- When done, the status says what was done, for example "English → Japanese", with a link **Show Original**.
- If the article is already in the target language, the status says so, for example "Already in Japanese", and nothing else happens.
- A failure is one short sentence in the row, never an alert: the language pair is not supported; the download was not allowed; the language pack is missing and the Mac is offline. If one paragraph fails, its original text stays and the row says how many failed.

**Language**

- The target is **Article Translation** in Settings (3.7). Its first item is **Match System**; then every target language the system reports, with localized names.
- Match System uses the first of the Mac's preferred languages that the system can translate into, compared by language and script (region ignored), or English if none can. It follows later changes of the Mac's preferences.
- A manual choice is remembered across launches until Match System is chosen again; changing the display language never changes it.
- The article button, `t` and the menu-bar command translate into that target or return to the original; the article button has no language menu.
- The button's help names the target, for example "Translate into Japanese or show original (t)".
- The button stays enabled when the article is already in the target language; a press shows the same-language status above, with the target's name, and translates nothing. The article's language is compared with the target, never with the display language.
- Changing the target starts no translation: a shown translation returns to the original and the button is off, running work is dropped, and the next press uses the new target.
- A remembered target that the system no longer reports is kept; a press shows the "pair not supported" sentence above.

The reason for the Settings choice and its default, and the cost of that default for a Mac in English, are in [decision 0060](decisions/0060-language-settings-and-ui-localization.md).

**Core rules** (decision 0054)

- A late answer for another article, another language, another press or a changed body is dropped. If a feed refresh changed the body, the translation is dropped, the original shows and the button is off.
- A translation is not stored: it is not in the library and not under the retention rules. It is kept in memory for a few recently translated articles and is gone when the app closes.
- Translating never blocks the main thread, and starts only when the person presses.

**Privacy.** Text never leaves the Mac. The only network use is the system downloading a language pack, which the system asks the person to allow. It does not need Apple Intelligence.

Not built: translating the original page, an "always translate" choice per subscription, original and translation side by side, translated titles in the list, links kept in the translated text.

### 3.7 Settings

The settings window (Unagi Reader ▸ Settings…, `⌘,`) has the panes below. Settings stay few: what is used often sits beside the content it acts on, not here. A choice about the article that is made once, such as its text size or its translation target, is here; the action it serves (the size keys, the translate button) stays beside the article.

| Pane | Holds, in this order | Code |
|---|---|---|
| General | the theme, the article's text size, and the display language with its note (below) | `ReaderSettingsView`, `AppearancePicker` |
| Articles | the article's translation target (3.6) and the retention period (3.3) | `ReaderSettingsView` |
| Shortcuts | the keys, to read | `ShortcutList`, `ReaderShortcuts` |

- **General** holds only how the app as a whole looks and speaks; a choice about articles goes to **Articles**. There is no Storage pane, and no Note pane until the note has a setting of its own
- The window opens on the pane that was shown last; a pane saved by an earlier version opens **General**
- Every choice is kept across launches and applies at once, except the display language (below).

**Language**

| Setting | Choices | Match System |
|---|---|---|
| **Article Translation** | **Match System**, then the system's translation languages | the first of the Mac's preferred languages the system can translate into, or English (3.6) |
| **App Language** | **Match System**, English, Japanese, Simplified Chinese, Traditional Chinese, Korean, Spanish, Brazilian Portuguese | chosen the way macOS chooses an app's language from the Mac's preferred languages (for example `zh-TW` gives Traditional Chinese), or English |

- The two choices are independent; a manual choice in either is remembered across launches until Match System is chosen again.
- The display language changes the app's own labels, menus, help, errors, status, shortcut descriptions and accessibility text, never the person's subscriptions, articles or note.
- The display language is the app's language in System Settings ▸ General ▸ Language & Region ▸ Applications: a change in either shows in the other. It applies at the next launch; below the choice, "Applies at next launch." The app does not restart itself.
- Only languages with bundled translations are offered; a missing UI translation falls back to English.
- The user guide names the display languages that were prepared with AI and not reviewed by a person, and says how to report a wrong translation (decision 0060).

**Theme**

| Tile | Look |
|---|---|
| **System** | Light or dark, as macOS is set. It never selects Sepia |
| **Light** | Always light |
| **Dark** | Always dark |
| **Sepia** | A light look on a warm paper colour |

- Each tile shows a small picture of the reader in that look instead of a description.
- Sepia covers the whole window: the reading surfaces (list, article, note and their bands) take the paper colour (#F4ECD8), and the sidebar a slightly darker one (#EADFC7). System controls and text are drawn light, with the light look's text colours, the selected row and the accent.
- In Sepia, body text has a contrast of about 13:1 on the paper (at least 4.5:1), and the secondary text of read rows and source lines is within 10% of its contrast on white. The values are in `SepiaPalette` and `AppPalette`.
- The app does not claim that a look rests the eyes.

**Text size**

- **Text Size** is a slider with five steps: 14, 16 (standard), 18, 20 and 22 pt.
- It sets the article's body. The title (26 pt at standard) and date line scale by the same ratio. The source name keeps the heading size of the other reading areas (3.1.4).
- The list, the sidebar and the note keep their sizes (decision 0028).
- A change shows at once in the open article; the paragraph at the top of the article stays at the top.
- Not now: `⌘+` / `⌘−` / `⌘0`, a size for the note or the list.

**Shortcuts**

- **Shortcuts** lists the keys of 3.1.5 and the note's keys, to read, grouped as **Reading**, **List**, **Original Page** and **Note**. Each row shows the key, what it does, and where it does not work (for example "Unavailable while typing").
- Help ▸ Keyboard Shortcuts opens Settings on this pane.
- The list is made from the same definitions the key handlers use, so it shows what the app does.
- Keys cannot be changed (the roadmap's "Not planned": key remapping).

## 4. How to decide

Use the [vision](vision.md)'s questions first. Then, in this order:

- **Reading never breaks:** no waiting, no lost position.
- **Opening is not interest:** read is history; Star is interest.
- **The person chooses what to keep:** nothing piles up on its own.
- **Honest about the input:** show what was fetched, as it is.

Never:

- Bypass a restriction to fetch more.
- Fill a missing body by guessing.
- Depend on a server holding the person's reading history.

## 5. AI

The app has **no AI of its own** ([decision 0049](decisions/0049-one-note-and-no-ai-of-its-own.md)). It never summarizes, suggests or writes into the note on its own, never sends text to an outside service, and never uses the network for AI. Everything works without AI.

### 5.1 Writing Tools in the note

- The note editor is a standard macOS text view, so the system shows **Writing Tools** (proofread, rewrite, tone, summary, key points, list, table, Compose and more) on a Mac with Apple Intelligence, for example from the right-click menu on selected text.
- Writing Tools act only when the person selects text and chooses them. The app adds nothing and does not promise their quality.
- On a Mac where they are not available, writing, editing and copying the note all still work.
- To summarize an article, the person pastes its text into the note and uses Writing Tools.

### 5.2 Giving the note to another AI

- The person presses **Copy Markdown** (3.3) and pastes the text into any AI (Claude, Codex, Gemini and so on). Text leaves the Mac only when the person pastes it.

## 6. Limits and what V1 does not build

**Platform and policy**

- macOS 27.0 or later (the support floor). CI builds for 26.6 ([decision 0065](decisions/0065-ci-and-local-verification.md)).
- The source is Apache-2.0. LICENSE and the third-party licenses, copyright notices and NOTICE are shipped. Feeds, articles, trademarks and service terms are not under the app's license.
- Only code, the specification and synthetic samples and tests are published; never the person's subscriptions, history, articles, note or credentials. Check the diff and the history before publishing.
- Publishing the source is a separate decision after product acceptance. The App Store and a signed release are not conditions of V1. Approving a policy is not permission to publish or distribute.

**Not built in V1**

| Area | Not built | Why |
|---|---|---|
| Platform | backend, accounts, sync, server-side fetching or AI, shared notes, push notifications | [vision](vision.md) |
| Subscriptions | nested folders, empty folders | 3.5 |
| Note | more than one note; folders, levels, tags, search or goals for notes; daily or weekly notes; system sharing services | decisions 0019, 0049 |
| Fetching | taking text from the original page (decision 0056); bypassing paywalls, subscriptions, logins or captchas; a full-text guarantee | section 4 |
| AI | an AI of the app's own (summary, draft help: a new decision is needed), keys or API calls in the app, AI off the Mac (Private Cloud Compute and the like), a dedicated link to one AI app (only **Copy Markdown**), sending or recording automatically, a guarantee of facts | decision 0049 |
| Settings | an in-app time zone setting; changing keys; a text size for the note or the list; themes other than the four of 3.7 | 3.7 |
| Old data | the prototype's Like and any migration of it (Star is a new mark) | decision 0001 |

Ideas for after V1, and the order of the work, are in the [roadmap](roadmap.md).

## 7. V1 acceptance scenarios

These are the conditions for passing, not a list of what has passed. "Where it is checked" names the place a condition can be checked; what only a real Mac can show is in the checklist of #145. A test that checks a scenario names its ID in a comment (`// PRD-02`), so `grep -rn "PRD-02" Tests` lists the tests of a scenario.

| ID | Scenario | Passes when | Where it is checked |
|---|---|---|---|
| PRD-01 | Read smoothly, with subscriptions in order | The four areas, the four layouts, appearance, folders and unread counts, the keys and the note open and close as in 3.1. No wrong body, no visible stall, no scroll jump; input, input methods and VoiceOver are not disturbed. The budgets of 2.1 hold | real Mac (the owner); parts in UI tests; 2.1 |
| PRD-02 | Open an article from the unread list | Scrolling the list keeps articles unread. Showing the body or the RSS summary saves the first read time | unit tests, synthetic app |
| PRD-04 | Write in the note | `n`, the button or `⌥⌘I` opens the note with the same motion as `v`: the article on the left, the note on the right, the keyboard in the note. The layout button adds the list (three columns). `j` / `k` move between articles with the note open; `Esc` or the ✕ closes it and returns to the screen before. Works without AI; still there after a restart, offline, after unsubscribing and after the body expires. Japanese input is not disturbed | UI tests, real Mac (Japanese input, VoiceOver) |
| PRD-05 | Give the note to another AI | **Copy Markdown** copies the text exactly; the person pastes it into any AI. The app starts no app, makes no file, uses no network. Disabled for an empty note | unit tests, real Mac |
| PRD-06 | (unused) | The app's own summary was removed by decision 0049; the number stays because other documents cite it | — |
| PRD-07 | Review the final demo | The owner sees this table and the product scope demonstrated and approves them explicitly. Until then the product is not accepted | the owner |
| PRD-08 | Set retention and deletion | The periods, the confirmations and "the note is never deleted automatically" of 3.3 hold. An expired body never looks readable | unit tests |
| PRD-09 | Read Stars again | The key and the button change the same state; the Star list can be read in order. Star, title and URL survive a restart and the body's expiry. Star and note are independent | unit tests, synthetic app |
| PRD-10 | (unused) | Sending a summary to a note was removed by decision 0049 | — |
| PRD-11 | Read many articles | Folders (open or closed as left, also after a restart), counts without duplicates, icons and article images work; a late, failed or offline image never changes the row height, the selection or the position | UI tests, real Mac |
| PRD-12 | (unused) | Removed by decision 0019 (unsorted Stars, theme suggestions) | — |
| PRD-13 | A Mac without AI | With Writing Tools unavailable, the note can be written, edited and copied, and the app uses no network for AI | real Mac (Writing Tools off) |
| PRD-14 | Add a subscription from a URL | As in 3.5: the check runs when typing stops; **Add** only when the feed was read; a site URL finds its feed; `http://` is checked as `https://`, and a feed only on http says that http is not supported; each failure has its sentence; an existing subscription is not added; the folder field appears only when it should | unit tests, synthetic app, real Mac (Japanese input) |
| PRD-15 | Move from another reader with OPML | File ▸ Import OPML…: subscriptions appear at once, articles arrive later, folders are one level, existing subscriptions do not change, the result is a short title and a line for each thing that was not plain success | unit tests, real Mac (the menu, a real OPML file) |
| PRD-16 | Manage subscriptions | Right-click: refresh, rename (in the row; Return on the selected row too), move to a folder, unsubscribe. Moving works with the chooser and with drag and drop | unit tests, real Mac (right-click, Return, drag) |
| PRD-17 | Narrow the list with a keyword | As in 3.1.4: `/` or the icon opens the filter; typing narrows the list to the articles of the scope whose title or feed summary contains it; clearing restores it; it stays across scopes and not across launches; `j` / `k` walk the filtered list; composing Japanese does not change the list | `ArticleFilterTests`, `ArticleFilterStoreTests`, `ReaderWorkspaceTests`, `ListFilterTests`; real Mac (the owner, with a library of several thousand articles; a real input method) |
| PRD-18 | Read an article in another language | As in 3.6: `t` or the button translates the open article and shows the progress and the result row; again shows the original; moving to another article shows the original; the text of the note, the list and the sidebar does not change; no text leaves the Mac | real Mac (the owner: a long English article into Japanese, a language pack download, a Mac without Apple Intelligence, VoiceOver); `ArticleTranslationTests`, `LanguageDecisionTests`, `TranslationTests`, `TranslationControllerTests` (a fake translator); the Settings target, Match System, the remembered choice, target help and a target change while a translation is shown: |
| PRD-19 | Send an article to the note | As in 3.3: `i`, `⌘K` (also with the keyboard in the note), the band button or Article ▸ Send Article to Note inserts `[Title](URL)`, or the article's selection as a quotation with its source link wherever the keyboard is, after the note's caret (at the end of a note never used), opening a closed note first; the keyboard stays where it was; one undo removes it; nothing is inserted while Japanese text is being composed; a failed save is shown; sending twice inserts twice; nothing else in the note changes | unit tests (`NoteClipTests`); UI tests (`NoteInsertionTests`, `SendToNoteTests`); real Mac (Japanese input, undo, VoiceOver, a long note) |
| PRD-20 | Choose the app language | As in 3.7: Match System and the bundled display languages are offered (all seven); Match System follows the Mac preferences or falls back to English; a choice applies at the next launch and matches System Settings; a manual choice survives restart; untranslated UI text falls back to English; article and note text stay unchanged; article translation keeps its own target | real Mac (menus, Settings, errors, shortcuts, accessibility labels and text expansion in each language; English and Japanese wording reviewed by the owner); `AppLanguageTests`, `CatalogTests` (temporary preferences, native matching, compiled resources and fallback) |

### 7.1 Conditions to ship 1.0

- The store schema is frozen as a `VersionedSchema` (architecture 3).
- CI runs a required check from the 1.0 release tag: a synthetic store with subscriptions, articles, read times, Stars and the note is opened by the new version and reopened, and nothing is lost. A skipped or not-run check is never a pass. It stays for every later model change (architecture 5).
- The Bundle ID, the store location, signing and the sandbox are fixed, and saving, restarting and updating are checked with them. Whether a beta store opens is checked; if it does not, the person is told how to keep it. [not built #451]
- The release is an ad hoc signed, not notarized DMG on GitHub Releases ([decision 0068](decisions/0068-an-ad-hoc-signed-dmg-on-github-releases.md)). A tag `vX.Y.Z` makes CI build it from that commit, with the version from the tag, its SHA-256 and a build provenance attestation, as a draft release. The owner checks that DMG on macOS 27 and publishes it; a published DMG is never replaced.
- The release notes say what changed, that the app is not notarized and how to open it, how to check the DMG, and that the library is kept.
