# 0065 Native window controls above the column bands

- Status: valid (the owner approved the tested prototype; product acceptance remains separate)
- Date: 2026-10-22
- Decider: the owner (PdM), in the chat of 2026-10-22, after reviewing the prototype and its loss of reading height.
- Replaces: the window and sidebar control placement in [0057](0057-each-column-has-its-own-band.md). Its column actions, common button style and menu commands stay. Also replaces the window-button spacing in point 4 of [0047](0047-the-way-back-is-a-cross-in-the-right-column.md).

## Decision

1. Use the native window toolbar for the window buttons, add subscription and refresh. Library actions stay available when the sidebar folds.
2. Keep the list, article, original-page and note actions in their own column bands, below the native window toolbar. The columns respect the native content safe area.
3. Prefer reliable standard window controls to keeping the old window appearance. Do not add custom full-screen exit buttons or a second shortcut.

The visible layout is in [specification 3.1.4](../specification.md#314-rules-per-area).

## Why

The vision promises a reading and writing loop with no interruption. Being unable to leave full screen breaks that loop. Keeping the old appearance is not a product goal.

In a packaged synthetic app on macOS 27.0.1, the hidden-title-bar configuration with no native toolbar drew the revealed green button but sent its click to the main window. Changing the title-bar style alone did not fix it. A real native toolbar with the library actions let the green button, the system shortcut and the View menu leave full screen. This comparison does not establish the internal AppKit cause.

The prototype kept column actions near their content. The owner accepted the extra toolbar height in exchange for standard window controls and less custom window code. Prototype checks are not final-build acceptance; the implementing pull request records that evidence.

## Not included

No new actions, settings, dependencies or data changes. Stage Manager, tiled windows, VoiceOver, Japanese input, Reduce Motion feel and long use remain outside this change's evidence.
