# 0049 One note, written beside the article; no hand-off and no AI of its own

- Status: valid; points 3 ("no source line") and 9 are changed in part by [0059](0059-send-the-article-to-the-note.md); how the note closes (point 4) is replaced by [0070](0070-closing-the-note-has-no-reverse-motion.md) (approved by the PdM when the PR that adds this record is merged)
- Date: 2026-10-12
- Decider: the owner (PdM), after a long run of trials with the note screen: "I think I found the truth." The owner proposed the whole change and answered each open point in chat. The details below follow the owner's answers.
- Replaces: [0019](0019-v1-simplification-notes.md) points 2, 3, 5, 6 and 8 (many notes in the sidebar, links made by sending, sending a summary, the summary settings, Claude from the note); 0020 (Git history); 0035 (Git history); 0042 (Git history); [0043](0043-rename-in-the-sidebar-row.md) for notes only (renaming a subscription stays); 0012 (Git history), 0021 (Git history) and 0022 (Git history) (the Claude hand-off); 0015 (Git history); the note-screen parts of [0046](0046-fold-the-sidebar-for-the-original-page-and-note.md) and [0047](0047-the-way-back-is-a-cross-in-the-right-column.md) (the ✕ and the fold on a note screen; the original page keeps both).
- Replaces in part: 0045 (Git history) (its remaining ideas about references, quotes and the review package no longer apply: there are no references and no package).

## Background

The owner had tried many shapes of the note: many notes, a note per subject, references recorded by sending a summary, a panel beside the article, a note screen, and a hand-off of the note to Claude. Each added something to manage or decide (which note, its name, deleting it, the destination menu, the references), and the code grew with bugs. The owner wants the product light and the code healthy: "delete code, keep it clean."

## Decision

1. **There is one note.** The app has exactly one Markdown note. There is no list of notes, no new note, no name, no rename, no delete, no undo of a delete.
2. **Existing data (the owner allows deleting it).** On the first start of the new version the most recently edited note is kept as the note; the other notes and all records that link articles to notes are deleted. With no note, an empty one is made. The store keeps the `Note` entity (one row); the entity that links articles to notes is removed. A store that cannot be opened is still never deleted by the app (decision 0003).
3. **`n` writes nothing into the note in v1.** There is no summary, no source line, no heading, no reference. The note is a plain memo.
4. **Opening the note: article on the left, note on the right.** `n` (when the person is not typing in an editable field), the note button in the toolbar and `⌥⌘I` open and close it, from any screen with an article list (Feeds, Star, a folder, a subscription). Opening is the same move as the original page (`v`): about 0.3 s, the sidebar and the list fold away to the left and the note slides in from the right (decision 0046 gives the motion). Closing is the reverse. Reduce Motion: no movement.
5. **Hopping through articles while writing.** A small 「一覧」 button at the top left of the article pane shows and hides the list. With it shown the screen is list, article and note: the person picks articles in the list while the one note stays fixed. `j` / `k` move to the next and previous article in both forms. The selected article and the reading position do not change when the note is opened or closed.
6. **The editor stays** (plain Markdown, light styling of headings and lists, autosave, Japanese input). The width of the note is set by dragging its edge, is kept between launches, and cannot be dragged shut (decision of #109).
7. **The AI that helps while writing is the system's Writing Tools** (Proofread, Rewrite, tone, Summary, Key Points, List, Table, Compose). The system puts them in the text view on a Mac with Apple Intelligence; the owner checked that they appear in the note. The app adds no AI of its own.
8. **The hand-off to Claude is removed** (the review screen, the managed copies, starting Claude Desktop, the share menu, the export to a file). One item stays: **「Markdownをコピー」** in the note's header, which copies the text exactly. The person pastes it into Claude, Codex, Gemini or anything else. The app starts no other app, makes no file and talks to no network for it.
9. **The on-device summary is removed** (sending a summary, the send menu, the summary settings, the Foundation Models call, the fetch of the original page for the AI's input). If it comes back, it will be an insertion at the caret designed to Apple's Human Interface Guidelines, in a new decision. Its code stays in Git history.
10. **Vision.** The Note and Ask AI parts of `docs/vision.md` no longer describe the product. The owner words the change; this record does not edit that file. Proposed meaning: "Read, then write your own note beside the article. For AI, use what the system offers in the text field, or copy the note to any AI you like."

## Order of work (each its own pull request, deletions first)

1. Remove the Claude hand-off; add 「Markdownをコピー」.
2. Remove the on-device summary.
3. One note: remove the note management and the article links (the store change; the first-start cleanup of point 2).
4. The new layout: `n`, the note button, the move, the list button.

The specification is changed in this pull request and is ahead of the code until those pull requests land. Architecture notes and the user guides (both languages) change with them. The store change gets an independent review (docs/review-checklist.md) and the opt-in store compatibility check.

## Not in this change

No code. The `docs/vision.md` edit. A new place to keep the note (a file): not now. A way to pass only a selected part of the note to an AI: not now (copy the selection with the system's own copy).

## Not verified

Whether the list can be folded with the system's split view: a first attempt (`detailOnly`) did not fold the list column (PoC of decision 0045). Settled in the step 4 pull request: the AppKit split view item folds it (`ListColumnCollapse`). The feel of the move on the owner's Mac. The opening of an old store that has links between articles and notes after the entity is removed: checked once on macOS 27 with the opt-in test of [verification 0049-one-note-store](../verification/0049-one-note-store.md); not on macOS 26.

## Sources

- The owner's messages in chat on 2026-10-12, including the screenshot of the Writing Tools panel in the note editor.
- Decisions listed above; specification 3.1, 3.2, 3.3, 5, 6 and 7.
