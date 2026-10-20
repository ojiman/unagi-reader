# Decision records

A decision record says who decided what, when and why. It is not where the current rules live: those are in the [specification](../specification.md) and the [architecture](../architecture.md). Read a record when you need to know why a rule is so.

## Rules

- One decision per file, `NNNN-title.md`. Fields: Status, Date, Decider, then Background or Why, Decision, and what it does not include. Short, facts only.
- Write a record only when a policy changes, or what a person can do or rely on (AGENTS.md, Definition of done 6). Layout, sizes, timings and wording go to the specification only.
- A new record that replaces an old one says so ("Replaces: NNNN"). In the same pull request, change the old record's Status. When the old record is wholly replaced, delete it from the working tree; Git keeps it (`git log --all -- docs/decisions/NNNN-*`).
- Take the next free number when you open the pull request; add one line at the end of the list below.
- Do not commit chat logs: they can hold personal data, and most of a discussion did not lead to the decision.

## Records in force

| Number | Decision | Status |
|---|---|---|
| [0001](0001-fresh-library-no-prototype-migration.md) | V1 starts with an empty library; no prototype migration | valid |
| [0003](0003-beta-data-compatibility.md) | No data compatibility between betas; guaranteed from 1.0 | valid |
| [0005](0005-v1-product-decisions-2026-10-04.md) | V1 product decisions: retention, source publication | valid in part (hand-off: 0049; display-language setting: 0060) |
| [0006](0006-original-page-and-sidebar-behavior.md) | Article selection and the sidebar while the original page is open | valid |
| [0007](0007-support-floor-macos-27.md) | Support floor macOS 27.0; the build floor stays 26.6 | valid |
| [0019](0019-v1-simplification-notes.md) | V1 simplification: notes replace themes | valid in part (points 2, 3, 5, 6, 8 replaced by 0049) |
| [0023](0023-rename-to-unagi-reader.md) | Rename to Unagi Reader | valid |
| [0024](0024-remove-the-old-name-from-code-and-scratch.md) | Remove the old name from code and scratch paths | valid |
| [0025](0025-refresh-feel.md) | The feel of a refresh | valid |
| [0026](0026-article-list-row-spacing.md) | More room in the article list rows | valid |
| [0027](0027-calmer-colours.md) | Calmer colours | valid |
| [0028](0028-article-list-type-sizes.md) | Article list: the headline leads | valid |
| [0029](0029-sidebar-header-plus.md) | A + in the sidebar section headers | valid |
| [0030](0030-one-reading-surface.md) | One reading surface | valid |
| [0031](0031-less-clutter.md) | Less clutter in the window | valid |
| [0032](0032-simple-add-subscription.md) | A simple "add subscription" sheet | valid |
| [0033](0033-rss-first.md) | RSS first: the feed's own text is shown | valid in part (points 3, 4 and 6 replaced by 0056) |
| [0034](0034-move-to-folder-chooser.md) | 「フォルダへ移動…」 is a chooser with a text field | valid |
| [0036](0036-check-the-feed-as-you-type.md) | Check the feed while the address is typed | valid |
| [0037](0037-choose-the-folder-when-adding.md) | Choose the folder when adding a subscription | valid |
| [0038](0038-find-the-feed-from-a-site-address.md) | Find the feed from a site address | valid |
| [0039](0039-the-unread-mark-is-the-source-name-colour.md) | The unread mark is the colour of the source name | valid |
| [0040](0040-try-https-first.md) | An `http://` address is checked as `https://` | valid |
| [0041](0041-import-opml.md) | Import subscriptions from an OPML file | valid |
| [0043](0043-rename-in-the-sidebar-row.md) | Rename in the sidebar row | valid for subscriptions |
| [0044](0044-original-page-slides-out.md) | The original page slides out when it closes | valid |
| [0046](0046-fold-the-sidebar-for-the-original-page-and-note.md) | Fold the sidebar for the original page and the note | valid for the original page (point 4: 0047; note parts: 0049, 0050) |
| [0047](0047-the-way-back-is-a-cross-in-the-right-column.md) | The way back is a ✕ at the top left of the right column | valid for the original page (note parts: 0049, 0050; the ✕ in the band: 0057) |
| [0048](0048-the-list-title-sits-below-the-band.md) | The list title sits below the toolbar band, level with the ✕ | the title stays below the band; layout replaced by specification 3.1.4 (2026-10-20) |
| [0049](0049-one-note-and-no-ai-of-its-own.md) | One note, written beside the article; no hand-off and no AI of its own | valid (points 3 and 9 in part: 0059) |
| [0050](0050-the-note-screen-closes-like-the-original-page.md) | The note screen closes like the original page; a layout button; a wider note | valid (point 4's place: 0057; the keyboard on opening: 0064) |
| [0051](0051-app-name-and-eel-icon.md) | App bundle filename matches Unagi Reader; orange eel icon | valid |
| [0052](0052-the-reading-screen-is-four-areas.md) | The vision describes the screen as four areas, not "three columns" | valid |
| [0053](0053-plain-http-feeds-are-not-supported.md) | Plain `http://` feeds are not supported; the sentence when the https form fails | valid |
| [0054](0054-translation-on-the-mac-not-stored.md) | Translation runs on the Mac with the system's framework, and is not stored | valid |
| [0055](0055-a-keyword-filter-for-the-list.md) | A keyword filter for the article list | valid (the magnifier's place: 0057) |
| [0056](0056-the-feed-text-only.md) | The article shows the feed's text only: no full-text fetch, no coverage line | valid |
| [0057](0057-each-column-has-its-own-band.md) | Each column has its own band; no system toolbar | valid |
| [0058](0058-unagi-reader-defines-its-own-requirements.md) | Unagi Reader defines its own requirements | valid |
| [0059](0059-send-the-article-to-the-note.md) | Send the article to the note: an insertion the person asks for; no AI summary | valid |
| [0060](0060-language-settings-and-ui-localization.md) | Language settings, independent defaults and AI-prepared UI localization | valid (built; product acceptance is separate) |
| [0061](0061-no-deleting-all-bodies-at-once.md) | No action deletes all article bodies at once | valid (built; no action deletes all bodies at once) |
| [0062](0062-several-writers-under-review.md) | Several writers at once, each on its own issue, under the owner's review | valid |
| [0063](0063-export-opml.md) | Export the subscriptions as an OPML file | valid (approved when its PR is merged) |
| [0064](0064-opening-the-note-gives-it-the-keyboard.md) | Opening the note gives it the keyboard | valid (built) |

## Removed from the working tree

Wholly replaced records are in Git history only: 0004, 0008, 0010, 0011, 0013, 0014, 0016, 0018 (first prune, 2026-10); 0009, 0012, 0015, 0017, 0020, 0021, 0022, 0035, 0042 (replaced by 0049) and 0045 (a proposal that 0049 made moot) (second prune, 2026-10-14); 0002 (replaced by 0062, 2026-10-18). Their numbers are not reused.
