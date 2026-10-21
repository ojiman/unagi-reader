# 0057 Each column has its own band; no system toolbar

- Status: valid in part; window and sidebar control placement is replaced by [0065](0065-native-window-controls-and-column-bands.md). Column actions, button style and menu commands remain.
- Date: 2026-10-14
- Decider: the owner (PdM), in the chat of 2026-10-14: the header felt inconsistent ("ガチャガチャしている"), two reference apps were shown, and the owner asked for it "to reach Unagi's vision". The three rules are the agent's proposal, which the owner accepted.
- Replaces the placement parts of: [0047](0047-the-way-back-is-a-cross-in-the-right-column.md) (the ✕ sat below the band), [0050](0050-the-note-screen-closes-like-the-original-page.md) point 4 (the layout button sat in the toolbar next to the note button), [0055](0055-a-keyword-filter-for-the-list.md) (the magnifier sat on the list title's line). Their behavior stays.

## Decision

1. **One band per column, at the top of the window.** The window has no system toolbar and no visible title bar. Each column (sidebar, list, article or original page, note) has its own band of the window's top height, in its own colour, and it folds with its column. There is no second row of controls below a band.
2. **A control sits in the band of the column it acts on.** The list's filter in the list band; the article's actions in the article band; the note's ✕, layout, arrows and copy in the note band.
3. **One style.** Monochrome symbols of one size and one hit area; colour only for a state (a filled Star, a filled translate). The translation status is short text in the article band.
4. **Nothing is only in a band.** Every band control also has a menu bar command (Apple's guideline for toolbar items), and the keys stay.

What the person sees is in the specification, 3.1.4 "Bands".

## Why

The owner's references put each column's controls in that column's top band; the app's own controls had grown wherever there was room, in four different styles. The system toolbar cannot do it: on 2026-10-14, in the real window (macOS 27.0.1), toolbar items attached to a column went to its leading edge, the note's items merged into the article's group, an item of a folded column stayed where the column was, and flexible spacers spread over the whole window. Without the system toolbar and with a hidden title bar, buttons drawn in a column's band showed and took real clicks, the window buttons stayed, and a drag on the empty band moved the window (the owner checked the drag by hand).

## Cost

The app draws the bands itself: window dragging on the empty band, full-screen behavior, accessibility labels and the menu bar commands are its own work. The controls inside stay the system's (buttons, the search field).

## Not verified

Full screen; Stage Manager and tiled windows; VoiceOver for the bands; macOS 26 (CI builds only).
