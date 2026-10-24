# 0050 The note screen closes like the original page; a layout button; a wider note

- Status: valid; the place of the layout button (point 4) is replaced by [0057](0057-each-column-has-its-own-band.md); where the keyboard goes when the note opens (point 1) is refined by [0064](0064-opening-the-note-gives-it-the-keyboard.md); the motion of closing (point 2) is replaced by [0070](0070-closing-the-note-has-no-reverse-motion.md) (approved by the PdM when the PR that adds this record was merged).
- Date: 2026-10-13
- Decider: the owner (PdM), after trying the build of PR #119 (the note beside the article), and in the chat that followed. The points come from the owner's answers; the wording and the proposal marked below are the Product Owner's.
- Refines: [0049](0049-one-note-and-no-ai-of-its-own.md) points 4, 5 and 6 (how the note screen is left, the 「一覧」 button, the width of the note).

## Background

With the note open (article on the left, note on the right) the owner found:

- `j` / `k` did not take the person back to the list, as they do after the original page (`v`). The owner first asked for the same here, then chose the simpler rule of point 1 (one rule for every layout, decided by where the keyboard is).
- `Esc` should close the note the same way, as it closes the original page.
- The note is a place to write, so it can be wider than the first width (380 pt).
- The 「一覧」 button at the top left of the article was not understood. The original page has a ✕ for closing; the note screen should have one too.
- The owner wants to keep the screen with the list, the article and the note together, and thinks of the screen as a few **layouts of the same one note** (not different notes). The owner asked to keep the control simple: one button.

## Decision

1. **`j` / `k` move to the next or previous article, in every layout, and the note stays open.** What they do depends only on where the keyboard is: in the article or the list they move the article; in the note's editor they are letters. To change the article while writing, use the arrows in the note's header (point 6). Only `Esc` and the ✕ close the note.
2. **`Esc` closes the note** (the move of decision 0049 in reverse) and shows the same article in the normal screen, with the list selection on it. It does nothing while Japanese text is being composed (the first `Esc` cancels the composition, as now). On the original page `Esc` is unchanged.
3. **A ✕ closes the note.** It sits at the top left of the note (the right column), as the ✕ of the original page sits at the top left of the page, and does the same as `Esc`.
4. **A layout button replaces the 「一覧」 button.** It sits in the toolbar next to the note button, so it is there when the sidebar is folded (the sidebar's own buttons are not). It is one button that **switches between two layouts** of the open note: *beside the article* (article and note; the list is folded) and *with the list* (list, article and note). It is disabled while the note is closed (the toolbar must not change height). The note button keeps its job: open and close. There are no more than these two layouts for now.
5. **The note is wider.** The first width is **640 pt** (today's largest width). The person can drag it up to **1,280 pt**. The smallest width stays **300 pt** (the owner chose this: no new limit; to be raised after trying it on a real Mac). **The width saved by an earlier version is dropped once**, so that the new first width is seen (the beta keeps no promise for this setting; the owner agreed). After that the width the person drags is kept. If the window is too narrow for the width, the note takes what is left after the article's smallest width (360 pt) and, in the three-column layout, the list's smallest width (280 pt); the owner will check this on a real Mac. In a 960 pt window the three columns just fit (280 + 360 + 300 = 940).
6. **The previous / next buttons in the note's header and `⌥⌘↑` / `⌥⌘↓` stay as they are.** They show the next or previous article beside the note and keep the note open; `j` / `k` cannot do that while the person types in the note.
7. **Not now (after dogfooding):** a key to switch the layout; a third layout with only the note on the screen (the wide note of point 6 comes close). A single button that cycles through more than two layouts is not wanted.

## Order of work (small pull requests, deletions first)

1. Replace the 「一覧」 button with the layout button; add the ✕ (points 3 and 4).
2. `Esc` closes the note (point 2). `j` / `k` already move the article with the note open; a test fixes that rule (point 1).
3. The wider note and the one-time drop of the saved width (point 5).

The specification (3.1, 3.3 and PRD-04) is changed in this pull request and is ahead of the code until those pull requests land. The user guides and the architecture notes change with them. PR #119 (step 4 of decision 0049) is merged.

## Not verified

How `Esc` and `j` / `k` feel when the keyboard is in the note's editor (they must not take the key while the person types: only `Esc` closes, and not during composition). Whether 1,280 pt is usable on a small screen. A 960 pt window with three columns. The macOS 27.0 support floor.

## Sources

- The owner's messages in chat on 2026-10-13.
- Decisions 0044, 0046, 0047 and 0049; specification 3.1 and 3.3.
