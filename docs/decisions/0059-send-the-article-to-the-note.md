# 0059 Send the article to the note: an insertion the person asks for; no AI summary

- Status: valid (approved by the PdM when the PR that adds this record is merged)
- Date: 2026-10-17
- Decider: the owner (PdM), in the chat of 2026-10-16 and 2026-10-17 while refreshing Settings (#235). The owner chose the format, the quotation and to drop the AI summary; the agent proposed the key `c` and the remaining details, and the owner adopted them as the starting point.
- Replaces in part: [0049](0049-one-note-and-no-ai-of-its-own.md) point 3 (the words "no source line"; `n` itself still writes nothing) and point 9 (the summary that might come back).

## Why

The loop is read → note → understand. To keep where a thought came from, the person had to copy the address in the browser and paste it. Decision 0049 removed the old sending because it kept records and menus the person had to manage. It said that if an insertion came back, it would be an insertion at the caret, in a new decision.

## Decision

1. **An AI summary will not be built.** 0049 point 9 left the door open ("if it comes back"). It is closed. A summary comes from the system's Writing Tools in the note, or from 「Markdownをコピー」 into an AI the person chooses (specification 5).
2. **One command, 「記事をノートに送る」, writes into the note when the person runs it.** It inserts `[Title](URL)`, or the selected text as a quotation with its source link, at the note's caret, as one undo step. It is run by `c` or the menu 「記事 ▸ 記事をノートに送る」; there is no button in a band. (The key became `i`, with `⌘K` on the menu, on 2026-10-24: #415. The article band got a button for it the same day: #417.)
3. **Nothing else changes.** The note stays one plain Markdown text. The app keeps no record, link or mark about the sent article, and opening the note still writes nothing. The rule "nothing writes into the note without the person" now reads: the person types, pastes, or runs this command.

The behavior is in specification 3.3; this record does not repeat it.

## Not in this change

No code. No whole-article insertion, summary, new note, automatic sending or list of sent articles. Sharing to other apps is postponed (#235).

## Not verified

How the insertion behaves with Japanese input methods, undo and VoiceOver on a real Mac.
