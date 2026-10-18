# 0064 Opening the note gives it the keyboard

- Status: valid (built)
- Date: 2026-10-18
- Decider: the owner, in the chat (2026-10-18), choosing between two options the agent described. Refines [0050](0050-the-note-screen-closes-like-the-original-page.md) point 1.

## Why

The note is opened to write in it. After `n` the keyboard stayed in the article, so the person had to click the note before typing. Decision 0050 point 1 kept the keyboard out of the note so that `j` / `k` would go on moving the article.

| Question of the vision | Answer |
|---|---|
| Does it make the loop smoother? | Yes: open the note and write, with no click between. |
| Does it add something to manage? | No. |
| Can it make the reader wait? | No. |
| Can text leave the Mac? | No. |

## Decision

1. **`n`, the note button and `⌥⌘I` open the note with the keyboard in its editor.** The caret is where the person left it; in a note they have not placed it in, at the end.
2. **「記事をノートに送る」 (`c`) does not move the keyboard** (specification 3.3, unchanged): the person is still reading.
3. **`j` / `k` keep the rule of 0050 point 1**: what they do depends on where the keyboard is. Right after the note opens they are letters in the note. To move the article, the person clicks the article or the list, or uses `⌥⌘↑` / `⌥⌘↓` and the arrows above the note.
4. Closing the note gives the keyboard back as before: to the list, or to the original page when it is still open (specification 3.1.3).

## Not verified

Japanese input right after the note opens; VoiceOver focus; macOS 27.0.
