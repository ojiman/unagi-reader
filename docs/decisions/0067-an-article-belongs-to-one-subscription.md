# 0067 An article belongs to one subscription

- Status: valid (built; approved when its PR is merged)
- Date: 2026-10-24
- Decider: the owner (PdM), in the chat of 2026-10-24, after a Cloudflare Blog article showed the name of Hatena Bookmark (#394, #395).

## Why

The app identified an article by its link alone. When two subscriptions carried the same link, it kept one article and joined it to both, so counts were not doubled. A social bookmark feed and the page's own site then met in one article: the list row showed the first subscription's name in the other's list, and each refresh wrote its own title, summary, image and date over the other's. Hatena Bookmark's date is the time the page was listed there, not the time it was published.

The owner: these are two things. A social bookmark feed says "this page was introduced here"; the site's feed says "this page was published". The cause is in the design, not in the display.

| Question of the vision | Answer |
|---|---|
| Does it make the loop smoother? | Yes: an article reads as the subscription it was opened from gave it. |
| Does it add something to manage? | A page two subscriptions carry is read twice. It happens only when one subscription introduces another's pages, or two feeds of one site overlap; the same address cannot be subscribed twice. |
| Can it make the reader wait? | No. |
| Can text leave the Mac? | No. |

## Decision

1. **An article is identified by its subscription and its entry**: the subscription's address plus the entry's link, or its source ID when it has no link. The same link in two subscriptions is two articles, each with its own feed's title, summary, image, date and body.
2. **Read state, Star and note records are not linked** between them. The app has no idea of "the same article" across subscriptions.
3. **Subscribing again to the same address** finds the articles kept after unsubscribing, with their reading history.
4. **A library made by an earlier version** is separated when it opens: a shared article stays in its own subscription (or, when that one is gone, in the first that still has it), with its reading history and Star; the other subscriptions get articles of their own at their next refresh, unread. Every article in a subscription gets the new identity at once, so point 3 holds before any refresh.

## What this costs

A page in a social bookmark feed and in its site's feed is counted and shown twice, and reading one does not mark the other.
