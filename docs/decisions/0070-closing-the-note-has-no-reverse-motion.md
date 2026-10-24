# 0070 Closing the note has no reverse motion

- Status: valid
- Date: 2026-10-25
- Decider: the owner (PdM), in the chat on the review of PR #454: record the new close as a decision that replaces the earlier points in part, in words that match what the app does.
- Replaces in part: [0049](0049-one-note-and-no-ai-of-its-own.md) point 4 ("Closing is the reverse") and [0050](0050-the-note-screen-closes-like-the-original-page.md) point 2 ("the move of decision 0049 in reverse").

## Why

The animated return made the article reflow while the note, the list and the sidebar competed for width (#215). Removing the note's and the list's motion made closing smoother; the numbers are in the [verification record](../verification/note-close-215.md).

## Decision

Closing the note (`n`, the note button, `⌥⌘I`, `Esc`, the note's ✕) is no longer the reverse of opening. The note goes and the list returns at once, without motion. The sidebar comes back with the system's own slide (about 0.25 s). Opening the note and switching its layout keep the move of about 0.3 s.

## Not included

Any change to opening the note, to the layout switch or to the original page (decision 0046 is unchanged).
