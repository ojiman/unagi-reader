# 0056 The article shows the feed's text only: no full-text fetch, no coverage line

- Status: valid (approved by the PdM when the PR that adds this record is merged)
- Date: 2026-10-14
- Decider: the owner (PdM), after trying the app on articles of www.nytimes.com, in the chat of 2026-10-14. The new wording of the vision's promise 2 was proposed by the agent and confirmed by the owner the same day.
- Replaces: [0033](0033-rss-first.md) points 3 and 4 (the button 「全文を取得」 and the quality check of extracted pages), and with point 4 below, point 6 (the one-time removal of extracted bodies). Changes the vision's promise 2.

## Decision

1. **No full-text fetch.** 「全文を取得」 / 「本文を再取得」 and the code behind it (page extraction, its quality check, the robots rules for pages) are removed. The owner: it nearly always ended in 「全文を取得できませんでした」, and an unstable feature goes unused. The whole article is read in the original page, `v` (in the app) or `b` (the browser).
2. **No coverage line** under the article (「RSS要約のみ」 and the others). How much text there is can be seen from the text itself.
3. **The vision's promise 2** no longer asks the app to say how much text it has. It now reads: "The source's text, as the source gives it. The app shows what the feed gives, and the original page is one key away. It does not fetch pages on its own, and it does not get around paywalls or logins."
4. **Saved data stays.** Bodies that earlier versions extracted are not deleted (decision 0003); they are shown like any body.

## What this costs

A feed that gives only a summary can be read in full only in the original page, and translation (3.6) works on the reader text only, so such an article is translated as its summary.
