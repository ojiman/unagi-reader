# 0047 The way back is a ✕ at the top left of the right column

- Status: valid for the original page; the ✕ moves into the band ([0057](0057-each-column-has-its-own-band.md)). The note-screen parts are replaced by [0049](0049-one-note-and-no-ai-of-its-own.md) and [0050](0050-the-note-screen-closes-like-the-original-page.md). The window-button spacing in point 4 is replaced by [0065](0065-native-window-controls-and-column-bands.md).
- Date: 2026-10-12
- Decider: the owner (PdM). Decision 0046 proposed a "<" next to the window buttons; the owner found its place awkward and not beautiful, and proposed the ✕ that already appears at the top left of the right column.
- Replaces: point 4 of [0046](0046-fold-the-sidebar-for-the-original-page-and-note.md) (the way back is not a "<" next to the window buttons).

## Decision

1. **Original page (`v`):** the control at the top left of the page, which was 「< 記事に戻る」, is now a ✕ (label and tooltip 「記事に戻る」, `Esc` does the same). It closes the page and brings the sidebar back.
2. **Note screen:** a ✕ at the top left of the right column leaves the note screen: it goes back to the screen the person was on before (Feeds, a folder or a subscription, with its selection and reading position restored, as for any return from a note) and brings the sidebar back. It is not the same as hiding the note's panel (the toolbar button and `⌥⌘I`). The owner confirmed this meaning on 2026-10-12.
3. **The sidebar button inside the list column goes away** when the note screen gets its ✕.
4. **The list title keeps clear of the window buttons.** With the sidebar folded the list reaches the window's left edge, and its title would sit under the window buttons; it starts to their right.

## Done in two pull requests

The original page (`v`) came first (the fold, the ✕ and the title), then the note screen (the fold, its ✕, the removal of the width rule and of the sidebar button in the list column, and `NoteScreenReturn` for the way back).

## Not verified

The motion at its real speed (it was checked slowed to 6 s for the page, and at its real speed with screenshots after the move for the note screen, in a synthetic copy with its own bundle identifier and demo data). Not checked: Esc and `j` / `k` closing (the same function), repeated `j`, Reduce Motion, VoiceOver, the feel on the owner's Mac.
