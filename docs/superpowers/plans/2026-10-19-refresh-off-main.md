# Refresh merge off the main thread (#303, W2 while refreshing)

A plan for several PRs; delete it when the last one merges. Follows [Writes through small contexts](2026-10-19-small-write-contexts.md) (steps 1 and 3 merged as #337 and #338). Nothing here is built yet. Step 0 was run on 2026-10-19: the design holds, with a plain actor instead of `@ModelActor` (results below).

## Why

After #338 each refresh batch (4 feeds) is merged and saved in a small context, but still on the main actor. In the reading-budget replay (100 subscriptions, 10,000 articles, 100 existing entries per feed) every batch still stops the main thread: 29 gaps of 165–520 ms, median 260–270 ms ([#338](https://github.com/ojiman/unagi-reader/pull/338)). W2 allows none over 100 ms. The save is no longer the main cost: the merge itself is (finding and updating 400 articles and their bodies, making memberships). Parsing already runs off the main thread (`FeedClient.fetch` in the task group). The budget stays as it is.

## The design

The batch's merge and save move to a background actor. The main actor keeps only what must touch the shown models: one refetch and the publication (both exist today).

1. **`RefreshWriter`, a plain Swift `actor`** holding the store's `ModelContainer` (which is `Sendable`). Not a `@ModelActor`: in step 0 its work ran on the main thread (below). One per refresh. For each batch it makes a **new** `ModelContext` (as #338 does on the main actor), so a long-lived context does not collect registered models and make its save walk them again (the cause of #249 and #303), and the batch's models go with it (#339).
2. **What crosses actors is values only**: feed IDs and their expected addresses, the parsed feeds (`ParsedFeed` is `Sendable`), the retention days, and the result (below). No `Article`, `Feed` or `ModelContext` crosses (the #303 constraint: do not move SwiftData models between actors).
3. **The entry index moves to the writer.** `EntryIndex` already holds IDs (#338). The writer builds it once per refresh from its own fetch (IDs, identity keys, memberships), off the main thread; this also removes the build from 50,000 articles at the first batch from the main thread.
4. **A batch** (in the writer): check each feed still exists with the fetched address (fetch by ID); prefetch the updated articles and bodies (as #338); merge; save once. On a failed save, the batch is dropped and each feed is merged and saved on its own, as today. The result, a `Sendable` value: the feed IDs written, the changed article IDs, the new membership keys, whether a title changed, and each failed feed's error.
5. **The publication** (main actor, one turn per batch): if a library write since the refresh started could make the result wrong (below), reload instead of publishing; otherwise refetch the batch's feeds, articles and memberships by ID (one fetch each, as #338) and run `publishRefresh`. Batches are published in order: the controller awaits each batch before it sends the next.

## How a change reaches the UI

Unchanged from the first plan: the main actor refetches by ID, which gives the shown instances the saved values without notifying them, so the store's own properties (counts, `contentRevision`, `feeds`) and the row values (title, icon address) carry the change. The publication is the same code as today.

## Writes from both sides: stale data and conflicts

This is the new risk: while the writer merges batch N, the person can read, Star, rename or unsubscribe on the main actor.

- **A library generation.** The store counts every library-context write that changes subscriptions, identities, memberships or content (`importFeed`, `importSubscriptions`, `unsubscribe`, `updateSubscription`, `moveFeed(s)`, `renameFolder`, `deleteContent`, `applyRetention`, `purgeExpired`, `reload` and `rollback`). A refresh records it when it starts. When it differs at a batch's publication, the writer rebuilds its index before the next batch, and the store reloads instead of publishing the stale result. Read marks and Stars do not change the generation: they do not touch what the writer reads to decide identities.
- **The same article written on both sides.** The writer changes an article's title, summary, dates, identity and content; the main actor changes its read time and Star. SwiftData does not document how a save that meets another context's newer save of the same row is merged, so **step 0 measures it**: a background save of an article's title after a main-actor save of its `isRead`. Accept the design only if neither value is lost. If the save fails instead, the writer refetches the article and applies the batch again once; if that is not possible, the design falls back (below).
- **A subscription removed during a refresh.** The writer checks each feed by ID when its batch starts; the publication drops IDs whose feed is gone (as `applyRefreshes` checks today).
- **Recovery.** A failed save in the writer never touches the library context. A failed refetch or publication: as today (errors reported, `rollback()`). The library context never holds an unsaved change (architecture 3.1).

## Unnecessary refetches

As the first plan: one fetch each for the batch's feeds, changed articles and new memberships; none for a batch that wrote nothing; none after a failed save; a full reload only when the generation changed.

## Step 0: probes before any PR (throwaway, not committed; run 2026-10-19)

1. Concurrent saves of one article: main-actor small context saves `isRead`; then a background context that fetched the article before that saves `title`. Record whether the save succeeds and both values survive, on macOS 27 locally and, through a CI test run on a branch, macOS 26.6 / Swift 6.3.3.
2. The main actor's share per batch: refetch plus `publishRefresh` for 400 changed articles, at 10,000 and 50,000 articles. It must stay well under 100 ms, or this design cannot meet W2.
3. The writer's index build from 50,000 articles off the main thread, and that the main actor has no gap over 100 ms meanwhile.
4. `@ModelActor` compiles and runs with the CI compiler (Swift 6.3.3). AGENTS.md lists three crashes or failures of that compiler on concurrency code (#14, #266).

Results (Release, macOS 27.0.1, Mac14,2, Swift 6.4, Mac idle; probes 1 and 4 also on CI, macOS 26.6.2, Swift 6.3.3, run 39182916259, every job passed):

| Probe | Result |
|---|---|
| 1. Concurrent saves of one article | The background save succeeds and both values survive (title, `isRead`, `firstReadAt`), from a `@ModelActor` and from a plain actor off the main thread, locally and on CI. The other order too: after the background save, a refetch shows the new title and the read state, with no unsaved change. |
| 2. Main actor's share per batch (refetch + `publishRefresh`, 400 articles) | 6.5–7.3 ms at 10,000 and at 50,000 articles (5 batches each, two processes). |
| 3. Index from 50,000 articles off the main thread | In a `@ModelActor` (made on the main actor or in a detached task, with its own or a new context) the work ran **on the main thread** and held it for the whole build (1.21–1.32 s). In a plain detached task with its own `ModelContext`: off the main thread, 1.16 s, longest main-actor delay 5.1 ms. |
| 4. CI compiler | `@ModelActor` and the plain actor compile and run with Swift 6.3.3; all regression, release and `ui-smoke` jobs passed. |

So the writer is a plain actor that makes its own contexts. The index build (about 1.2 s at 50,000 articles) delays the first batch's publication, not the window.

If probe 1 had lost a value, or probe 2 had been over about 50 ms, the alternative was to keep the merge on the main actor and split each batch into smaller main-actor turns (one feed per turn, yielding between them).

## Steps (one PR each, each with an independent review)

1. The library generation and its tests (no behavior change).
2. `RefreshWriter` with the index and the batch merge; `applyRefreshes` awaits it; publication on the main actor. Tests: everything `RefreshBatchTests` and `RefreshIndexTests` check today; a subscription removed during a refresh; a read mark and a Star on an article that the batch updates; a generation change between batches; cancellation.
3. Measurements: the reading-budget replay (W2 while refreshing, alternating with main), the first refresh at 200, 1,000 and 2,000 feeds, and peak RSS (#339).

## Not in this plan

Reading stalls (#249: profile first), the memory increase of #338 (#339, though step 2 may change it), `setRead` / `setStar` through small contexts.
