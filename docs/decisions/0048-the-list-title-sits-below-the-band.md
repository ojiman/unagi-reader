# 0048 The list title sits below the toolbar band, level with the ✕

- Status: the title stays below the band; its old two-line layout, size and alignment are replaced by [specification 3.1.4](../specification.md#314-rules-per-area) (owner, 2026-10-20). The ✕ moved into the band in [0057](0057-each-column-has-its-own-band.md).
- Date: 2026-10-12
- Decider: the owner (PdM) saw that the ✕ of the right column sits lower than the list title 「すべての記事」, asked to lower the title to the ✕'s height, and showed a reference app's middle column (the toolbar band with the actions, the title block below it). The owner also plans a keyword filter in the middle column, which will go into the band as an icon, as in that reference. This change is the layout only. The details below are the Product Owner's.
- Refines: [0047](0047-the-way-back-is-a-cross-in-the-right-column.md) point 4 (the title no longer needs to keep clear of the window buttons).

## Decision

1. **The title block (the name, and 「N件の記事」 under it) moves out of the toolbar band to just below it.** The band keeps the window buttons (and, later, the actions of this column). The title is larger (17 pt, semibold); the count stays 11 pt.
2. **The first line of the title is level with the ✕ of the right column** (the ✕ of the original page and of the note screen). The distance of the ✕'s centre from the band (16 pt) was measured in the running app and is one constant (`ListHeader.crossCentre`); a test checks that the title's first line is within 4 pt of it and that nothing is drawn in the band.
3. **The list leaves room for the block** (`headerInset`, added to the toolbar's own inset of the scroll view), and the block has the surface colour, so rows that scroll up do not show through it.
4. **The way for the keyword filter:** the band of the middle column is free for its icon, and the block below the band does not move when it comes. The filter itself is a separate change.
5. **The ✕ stays where it was** (at the top left of the right column, below the band). Putting it into the band, level with the window buttons, was tried: as a drawn overlay it did not show and did not take clicks (the title bar covers it), and as a real toolbar item it works but the system puts it at the left of the whole window, next to the window buttons (over the list), which is where the owner did not want the "<" of 0046. Putting it above the right column needs an AppKit toolbar item tied to the split view's divider; that is not done here.

## Not in this change

The keyword filter and the other actions in the band (for example 「すべて既読」). The ✕ in the band.

## Not verified

Checked in a synthetic copy of the app (own bundle identifier and demo data) by screenshots: the title block below the band with the rows below it, the title's first line level with the ✕ on the original page and on the note screen (the ✕'s centre at y≈68 of the window). Not checked: very narrow columns, long names (the ellipsis test still passes), a different system (the band's height, 52 pt, is the toolbar's standard height and the system does not report it), VoiceOver, the feel on the owner's Mac. `ReaderLayoutTests.originalPageKeepsColumnsAndSidebarControlsMounted` fails on this Mac (macOS 27) with and without this change, while CI passes it; it is reported separately.
