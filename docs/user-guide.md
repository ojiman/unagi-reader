# Unagi Reader user guide

How to start Unagi Reader, how it keeps your data, and how to use it. This guide shows labels in Japanese with their meaning, for example 「Markdownをコピー」 (Copy Markdown). If this guide and the app differ, the [specification](specification.md) decides; please tell us.

## 1. Start the app

You need macOS 27.0 or later and the Swift toolchain from Xcode. From the project folder:

```sh
bash scripts/build-app.sh release
```

This makes `.build/Unagi Reader.app`; open it from Finder. It is ad hoc signed, not signed with a Developer ID and not notarized.

To look around without your real library, start a separate copy with synthetic subscriptions:

```sh
bash scripts/make-synthetic-copy.sh
```

Run the launch command it prints. It uses a temporary app with its own bundle ID and a fresh data directory. Keep `open -n`: without it, macOS can reuse a running Unagi Reader and ignore the arguments. Before using it, check `pgrep -fl UnagiReader` for that temporary `--data-directory` and check the demo subscriptions in the window: 「開発ノート」, 「テクノロジー」 and 「週末の読み物」.

## 2. Your data

- The library is `~/Library/Application Support/UnagiReader/Reader.store`. A new library starts empty. Restarting the same version keeps everything.
- **During the beta, a new version may not open an older library.** The app then shows 「ライブラリを開けませんでした」 (Could not open the library) and never deletes or recreates it by itself. From 1.0, data is kept across updates.
- If an older library with several notes can be opened, the app keeps only the note you edited last and deletes the other notes. This cannot be undone; back up before updating. This does not guarantee that every older beta library can be opened.

### Back up the library by hand

Do this before you update a beta, or when the app cannot open the library and you want to start again empty. These steps have not been tried on a real Mac yet.

1. Quit Unagi Reader (⌘Q).
2. In Finder choose Go ▸ Go to Folder (移動 ▸ フォルダへ移動) and open `~/Library/Application Support/`.
3. Rename the whole `UnagiReader` folder, for example to `UnagiReader-backup-20261014`. Keep `Reader.store`, `Reader.store-shm` and `Reader.store-wal` together; do not copy only one file.
4. Start Unagi Reader. It makes a new, empty library. Keep the renamed folder until you have checked the new one. A backup is not a promise that the data can be converted back.

## 3. Using the app

### The screen

The window has four areas: the sidebar, the list, the article and the note. Normally you see the first three. `v` shows the original page (the sidebar folds away and the page takes its place). `n` shows the note beside the article (the sidebar and the list fold away); the layout button at the top left of the note, next to its ✕, brings the list back beside them, and hides it again. Settings ▸ 「一般」 has the appearance (system, light, dark or sepia, a light look on a warm paper colour) and 「文字サイズ」, the article's text size in five steps from 14 to 22 pt; the title follows it, the list and the note keep theirs.

### Subscriptions and folders

- **Add:** click ＋ at the top right of the sidebar and type an RSS or Atom address, or a site's address (the app finds the feed the page announces). An `http://` address without an explicit port is checked as `https://`. When you stop typing, the line under the field shows 「✓」 and the feed's name, or why it could not be read. 「追加」 (Add) works only when the feed was read and is not already subscribed. Return also adds; if the check is still running, it waits for the result.
- **Folder when adding:** if you have folders, a folder field appears once the feed is read. Press Return to add it unfiled, or type to choose a folder; a new name offers `「Work」を作って追加` (Create “Work” and Add), for example. Pick it, then press 「追加」. The ＋ on a folder row adds straight into that folder.
- **Import from another reader:** File ▸ 「OPMLを取り込む…」 (Import OPML). The subscriptions appear at once and their articles follow. Existing subscriptions do not change. Folders are one level deep.
- **Take your subscriptions out:** File ▸ 「OPMLを書き出す…」 (Export OPML), then choose where to save. The file holds your subscriptions and folders, not articles, read state, Stars or the note. Another reader, or this app, can import it.
- **Manage:** right-click a subscription to refresh, rename (in the row; Return on the selected row too), move to a folder, or unsubscribe. 「フォルダへ移動…」 (Move to folder) opens a chooser: type to narrow, or type a new name and choose `「Work」を作って移動` (Create “Work” and Move), for example; 「未分類」 (unfiled) moves it out. You can also drag a subscription onto a folder, or onto the 「購読元」 heading to unfile it.
- Right-click a folder to rename it; a name that already exists joins the two folders.
- Hold ⌥ (Option) while you click ＋ for the troubleshooting tools (feed XML by hand, a synthetic sample).

### Refresh

The app refreshes at launch, when you come back to it, and every 30 minutes; the refresh button at the top of the sidebar refreshes by hand, and its arrow turns while it works. New articles slide into the list where they belong; if you have scrolled down, the list stays where you are. If a download fails, the saved articles can still be read.

### Reading and keys

The app also lists these keys in Settings ▸ 「ショートカット」 (Help ▸ 「ショートカット一覧」 opens it).

| Key | Action |
|---|---|
| `j` / `k` | Next / previous article |
| `m` | Read / unread |
| `s` | Star on / off |
| `n` | Open or close the note (also the note button at the top of the article and `⌥⌘I`) |
| `i` | Send the article to the note: its title and link, or the text you selected in the article as a quotation (also `⌘K`, the button beside the note button at the top of the article, and 記事 ▸ 記事をノートに送る) |
| `t` | Translate the article into the target in Settings ▸ 「記事」 ▸ 「記事翻訳」, on your Mac; again shows the original (also the button at the top of the article and 表示 ▸ 翻訳). The first time, macOS may ask to download the language |
| `/` | Narrow the list: type words from the titles or summaries (also the magnifier at the top right of the list). The field stays while it has text; empty, a click elsewhere closes it |
| `b` | Open the original page in your browser |
| `v` | Open the original page in the app. The ✕ at its top left, `Esc` or choosing another article closes it |
| `Esc` | Back to reading: closes the original page, or the note. With both open, it closes the one you are in; press it again for the other |

- Single-letter reading keys and `/` do not act while you type in a field or compose Japanese text. In the note, `Esc` first cancels composition. `j`, `k`, `s` and `n` also work on the original page, outside its text fields.
- An article becomes read when its body or RSS summary is shown, not when you scroll past it in the list. If neither is available, selecting it does not mark it read.
- The app shows the feed's own text (or its summary), as the feed gives it. For the whole article, open the original page with `v` (in the app) or `b` (your browser). The app never gets around paywalls or logins.
- The in-app browser does not keep you signed in to sites.
- `s` or the button at the top right stars an article; the Star list shows them again.

### The note

There is one note and nothing to manage: no list, no names, no delete.

- `n`, `⌥⌘I` or the note button at the top of the article opens it beside the article in a short move, ready for typing; the same again, or the ✕ at the top left of the note, closes it and returns you to where you were. It is the same note on every screen.
- It is plain Markdown in your own words, saved as you type, exactly as typed. A line starting with one to six `#` marks followed by a space (or the line end) is shown as a heading. A line starting with `- `, `* `, `+ `, `1. ` or `1) ` is shown as a list item. Only the look changes, never the saved text. Paste adds plain text only.
- `j` / `k` change the article while the note stays open, when the article or the list has the keyboard: click the article first, since an opened note has it. While you write, `⌥⌘↓` and `⌥⌘↑` change the article, and so do the two arrows above the note.
- Drag the panel's edge to change its width; the width is kept.
- `i` (or `⌘K`, the button beside the note button, or 記事 ▸ 記事をノートに送る) puts the article into the note after the caret or selection you left there, keeping selected note text: its title and link as `[Title](URL)`, or the text you selected in the article as a quotation with that link. The selection stays in the article, in grey, while you write in the note, and it is still quoted; choosing another article clears it. Each one is a paragraph of its own, and a short highlight shows where it went. With a translation shown, only the title and link are sent. A closed note opens and takes it at its end. `⌘K` also works while you type in the note, so you can send an article and go on writing. The command does nothing while you compose text in any field or view the original page. One undo removes it. Nothing else ever writes into the note.
- 「Markdownをコピー」 (Copy Markdown) at the top of the note copies its exact text. It is disabled when the note is empty or contains only whitespace.

### Language settings

The two language choices are independent: App Language (「表示言語」) is in Settings ▸ General (「一般」), and Article Translation (「記事翻訳」) is in Settings ▸ Articles (「記事」). App Language (「表示言語」) offers Match System, English, Japanese, Simplified Chinese, Traditional Chinese, Korean, Spanish and Brazilian Portuguese. It shares macOS's per-app choice in System Settings ▸ General ▸ Language & Region ▸ Applications. It applies at the next launch; quit and open the app when ready. Match System follows your Mac's preferred languages, with English as the fallback. It never translates your subscriptions, articles or note. Labels quoted in this guide are the Japanese labels.

The Simplified Chinese, Traditional Chinese, Korean, Spanish and Brazilian Portuguese translations were prepared with AI and have not been reviewed by a person. If wording is wrong, [open an issue](https://github.com/ojiman/unagi-reader/issues/new) with the language, screen, current wording and suggested wording.

Choose 「システムに合わせる」 in 「記事翻訳」 to follow the Mac's preferred languages, or choose a fixed target. A change returns the open article to its original; press `t` to translate into the new target. An article already in the target language stays in its original with a short status message.

## 4. AI

The app has no AI of its own. It does not summarize, suggest or write, and it never talks to an AI service.

- **While you write:** on a Mac with Apple Intelligence, select text in the note and right-click for the system's Writing Tools (proofread, rewrite, summary, list, table and more).
- **To ask another AI:** press 「Markdownをコピー」 and paste the note into the AI you like. Nothing leaves your Mac unless you paste it yourself.

## 5. How long data is kept

- Article texts and summaries: 30 days by default; choose 7, 30, 90 days or 「1年」 (1 Year, 365 days) in Settings ▸ 「記事」 ▸ 「保持期間」. The days count from first receipt until the first reading, then from that first reading. Fetching again, marking unread or adding a Star does not restart the clock.
- When the text expires, the title, the link and the Star stay.
- Shortening the period asks you first.
- **The note never expires.** The older-library cleanup described in section 2 is a separate beta upgrade step.

## 6. For developers

Commands, tests, CI and the rules for contributors are in [AGENTS.md](../AGENTS.md); how the app is built is in the [architecture](architecture.md).
