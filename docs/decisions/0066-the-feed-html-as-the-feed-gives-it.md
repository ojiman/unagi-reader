# 0066 The article shows the feed's HTML as the feed gives it, in native text

- Status: valid (built: #406 images, #407 structure)
- Date: 2026-10-24
- Decider: the owner (PdM), in the chat of 2026-10-24, choosing option B of the two the agent described.

## Why

A Hatena Bookmark entry's `content:encoded` holds the site's favicon, the linked title, the entry image, the summary, a bookmark-count image (「165 users」) and the B! button. Another reader shows all of them. Unagi Reader showed the title and the summary under one image: `ArticleMarkup` drops every `img`, and headings, lists, code and tables become plain paragraphs.

The owner: RSS is made to carry this HTML, and a reader that does not show it loses its generality. No reader can handle every site one by one, so the app follows what the feed gives. Promise 2 of the vision already says so: "The source's text, as the source gives it. The app shows what the feed gives."

Two ways were weighed:

| | A. Draw the HTML in a web view | B. Keep native text, follow the HTML |
|---|---|---|
| Fidelity | High, including complex layout | Most of what articles use: paragraphs, headings, links, quotes, lists, code, images, simple tables |
| The loop (selection, 「記事をノートに送る」, translation, keys, reading position) | Built again on a web view | Kept as it is |
| Work | Large | Medium |

| Question of the vision | Answer |
|---|---|
| Does it make the loop smoother? | Yes: the article reads as its source wrote it, and the note and translation keep working on native text. |
| Does it add something to manage? | No. There is no setting. |
| Can it make the reader wait? | Not if a late image never moves the text being read (point 3). |
| Can text leave the Mac? | No. Loading an image tells its server that the article was opened, as the representative image already does; no text is sent. |

## Decision

1. **The article shows the feed's HTML as the feed gives it**, in the native text view: images where the feed puts them (#406), and headings, lists, code, emphasis and simple tables (#407), next to the links and quotes it already keeps.
2. **No handling per site or per feed.** Bookmark counters, favicons and buttons in a feed's HTML are shown because the feed has them. The choice of the representative image for the list (architecture 4.5) is a separate matter and does not change.
3. **Nothing waits, nothing runs.** Scripts, styles, forms and frames stay dropped. A late, failed or offline image never moves the text the person is reading.
4. **The loop keeps working.** Selection, copy, 「記事をノートに送る」, translation, `j` / `k` and the read mark work as before.

## What this costs

Layout the native text cannot express (CSS, complex tables, embedded media) is lost; the original page is one key away (`v`, `b`). The body's saved format grows; saved bodies without the new data are shown as before until their feed refreshes (decision 0003).
