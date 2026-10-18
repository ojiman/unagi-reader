# 0033 RSS first: the feed's own text is shown

- Status: valid in part: points 3, 4 and 6 replaced by [0056](0056-the-feed-text-only.md) (approved by the PdM when the PR that adds this record was merged; the one-time removal of point 6 stopped running in #250, as 0056 point 4 says)
- Date: 2026-10-12
- Decider: the owner (PdM) saw a broken article in the reader (the menus and counters of a web page) while the same article was clean in another reader, and proposed to show the RSS as it is and to go to the original with the v or b key. The owner approved the first proposal of the Product Owner (the agent), who gave the points marked "PO".

## What was found

The feed (RSS 1.0, from Hatena Bookmark) was parsed correctly: 30 entries, none skipped, the title, the summary, the quoted `content:encoded` and the image all as the feed has them. The broken view came from the page extraction: on opening an article the app fetched the original page and replaced the feed's text with the paragraphs of the page's first `<article>`. On the page of one article that element holds breadcrumbs, a date, tags and counters ("トップ", "2026年", "27", "94", "ポスト", "いいね！0"), which became 102 paragraphs.

## Decision

1. **Opening an article shows the feed's text and never fetches the page.** Nothing waits, and no request goes to a third-party site just because an article was opened. *(Owner.)*
2. **Details are read in the original page** with `v` (inside the app) or `b` (browser). Both exist already.
3. **The full text from the page is a button, not a default.** 「全文を取得」 (「本文を再取得」 once extracted) fetches and extracts the page, and shows and saves the result. *(PO.)*
4. **A page that is mostly page chrome is not taken as the article** (`ExtractionQuality`): a page with fewer than 400 letters in all, where more than half of the paragraphs are tiny (shorter than 6 characters, or without a letter), is not used. A page with plenty of text is used even if it has many short headings and list items. This catches small pages made of fragments; it does not catch every noisy page (a page of embedded posts, with plenty of text, can pass), which is why the extraction is no longer automatic. Short lists with little else (release notes of a few words, a recipe's ingredients) are rejected too; they can be read in the original page.
5. **For the AI summary, a short feed text is replaced by the page text at send time.** Only when the person presses the send button, AI is on, **the model is available**, **the article's text is within retention** (expired text is never brought back, not even through a page), and the feed text is shorter than 1,000 characters. The page is fetched (robots rules kept, no redirects, 10 seconds at most) and its text is the input of the on-device model. It is neither shown nor saved; a page that cannot be used leaves the feed text as the input. Cancelling or turning AI off during the fetch stops the send before the model runs. A send can therefore take up to about 30 seconds (10 for the page, 20 for the model). *(PO.)*
6. **Bodies that were taken from pages by earlier versions are removed once per library**, at the first start with this version (`discardExtractedBodiesOnce`; the marker is a file `.extracted-bodies-discarded-v1` in the library's folder, so a copy or a renamed folder does not run it again, and a failed save is retried at the next start). Every body whose coverage is "extracted" goes, including one that the person asked for earlier with 「本文を再取得」. The article keeps its RSS summary. For an item that is still in the feed, the next refresh brings back the feed's own body. For an item that has left the feed, or a feed that gives its text only in `content:encoded` or Atom `content`, only the summary (possibly nothing) remains; 「全文を取得」 is offered whenever the article is within retention, so the text can be fetched again. Notes are not affected (they hold their own title, URL and summary). *(PO.)*

Limits: after 「全文を取得」 the feed's text is not shown again for that article (a feed refresh does not replace an extracted body); the original page stays one key away (`v`, `b`).

## Not verified

The removal on a real library (it runs once at the first start with this version); the summary quality when the page text is used (needs the on-device model); other noisy pages; the button 「全文を取得」 on a real site; the removal and the retry on macOS 26 (CI).
