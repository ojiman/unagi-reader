# 0063 Export the subscriptions as an OPML file

- Status: valid (approved by the owner when the pull request that adds this record is merged)
- Date: 2026-10-18
- Decider: the owner put OPML export in the roadmap for whoever has room (#130). The details below are the agent's, for the owner to approve in review.

## Why

[0041](0041-import-opml.md) brought subscriptions in; there was no way out. The vision promises that the person's data stays theirs: no account, no backend. Someone who tries the app must be able to leave with their subscriptions, and OPML is the format every other reader reads.

| Question of the vision | Answer |
|---|---|
| Does it make the loop smoother? | Not the loop itself; it makes trying the app safe. |
| Does it add something to manage? | One menu item, used rarely; no setting. |
| Can it make the reader wait? | No: nothing is fetched, and writing a list of subscriptions takes no visible time. |
| Can text leave the Mac? | Only into a file the person chooses. |

## Decision

1. **One entry: File ▸ 「OPMLを書き出す…」**, under 「OPMLを取り込む…」, with no key shortcut. It is on when the window that shows the library is the active one. The standard save panel suggests 「Unagi Reader Subscriptions YYYY-MM-DD.opml」.
2. **What is written:** an OPML 2.0 file in UTF-8. Each folder is an outline that holds its subscriptions (one level, as in the app), in the order of folder names; the unfiled subscriptions follow at the top level. Each subscription has `type="rss"`, `text` and `title` (its name in the app), `xmlUrl`, and `htmlUrl` when the site is known. Names are escaped; characters that XML does not allow are left out.
3. **Nothing is fetched**, so it works offline. Importing the file into an empty library gives the same subscriptions and folders. **There is no limit**: every subscription is written, also beyond the import's 2,000 per file (the owner, 2026-10-18), because the export is the way out and another reader may take more. A pending reload of the library runs first; if it fails, nothing is written and the reason is shown.
4. **A failure is shown, never dropped:** when the file cannot be written, an alert 「購読を書き出せませんでした」 gives the reason. Cancelling the panel does nothing. A written file needs no message.

## Not included

Articles, read state, Stars and the note (the note has 「Markdownをコピー」). Automatic or scheduled backups. Choosing which subscriptions to export.

## Not verified

The menu item, the save panel and the alert in a real window: the test tools cannot open menus. They are covered by building the app; the file and the flow (a failed write, a cancel) are covered by unit tests.
