# Writes through small contexts (#249, #303)

A plan for several PRs; delete it when the last one merges. The rule that stays goes to architecture 3 (the first PR adds it).

## Why

A save in the library context (`ReaderStore.context`) walks every model registered in it. `reload()` registers all articles and memberships, so even one changed field costs in proportion to the library. Throwaway probe, Release, macOS 27.0.1, Swift 6.4, median of 20 saves of one changed `isRead` ([#249 comment](https://github.com/ojiman/unagi-reader/issues/249)):

| Articles | Save in the library context | New small context: fetch by ID + save | Library context: refetch by ID |
|---|---|---|---|
| 10,000 | 7.9–8.4 ms | 0.45–0.51 ms | 0.13 ms |
| 30,000 | 30.2–31.8 ms | 0.49–0.52 ms | 0.14 ms |

The note already left the library context for this reason (#332). The read mark comes with every article shown (#249); a refresh batch saves about 240 ms at 1,000 feeds (#303).

## The write path

1. `reloadIfNeeded()` first, as every change (architecture 3.1).
2. Decide from the library context's models, resolved by ID, whether there is anything to write. Nothing to write: return before any context is made.
3. Make a new `ModelContext` on the same container (autosave off). Fetch only the models to change, by ID. Change them. `saveHook`, then save.
4. A failed save: `rollback()` (both contexts are replaced and the library is reloaded) and throw. The small context is dropped; nothing of it is shown.
5. A saved change: fetch the same models again **by ID** in the library context. This gives the registered instances the saved values. Then update the store's own indexes and counts (`updateUnreadCounts`, as before), and change the revision (below).

## How a change reaches the UI

- A refetch gives the library context's instance the saved values, but **does not notify** its observers (probe). Setting the same value again would notify them, but leaves the library context with an unsaved change, which 3.1 forbids. So views must not rely on observing a model's own properties for a value written this way.
- The store tells them instead: `readRevision` (an observed property of `ReaderStore`) changes once per saved read mark. A view whose output depends on read state reads it in its `body` (today `ReaderView.selectedExpiry`, which shows the retention deadline from `firstReadAt`).
- The unread counts (`unreadCount`, `feedUnreadCounts`, `folderUnreadCounts`) are store properties and change as before, so the sidebar and the scopes update as before.
- The article list is AppKit: each `ReaderView` update reloads its visible rows (`NativeArticleList.Coordinator.update`), and each row reads `isRead` from the refetched instance. A changed count or revision runs that update.
- For each new write path, list what shows the written values, and make sure each of them reads a store property that the write changes. A hosted test covers what a test can see.

## Stale models

- The library context never holds an unsaved change (3.1): every change is saved at once. So a refetch never meets a change it would overwrite or merge with.
- A small context lives for one write. It is never kept, shared or shown, so it cannot go stale.
- If the save succeeded but the refetch failed (not seen so far), the write is done and is not reported as failed (3.1, "never reported as done" works both ways). `needsReload` is set, so the next change reloads the library first and the views show the saved values.
- After a failed save, `rollback()` already replaces the library and note contexts and reloads; references taken before a failure are not used again (models are resolved by ID).
- A save from another context of the same store is not merged by itself. Only the models a write changed are refetched; the store does not depend on any other model being fresh. A write path that changes models it does not refetch must reload instead.

## Unnecessary refetches

- Refetch only what the write changed, by ID, one fetch per write (the read mark: one article). Never refetch the library or a scope.
- No context, save or refetch when there is nothing to write (step 2: an already read article that has its first read time).
- No refetch after a failed save: `rollback()` reloads anyway.
- A batch (a refresh, #303) refetches the changed and new articles of that batch with one fetch for their IDs, not one per article. Its new models are fetched once, so the store's indexes take the library context's instances.

## Validation and measurement

- Tests for each write path: it does not commit an unrelated pending change of the library context; the shown model takes the saved values and the revision changes; a failed save is not shown, not saved and can be retried; the failed-reload path is blocked as before (`ReaderStoreTests`).
- Save latency: an opt-in Release test on the `BenchmarkFixtureTests` library times a one-field save in the library context against the new path, each in the same process.
- UI refresh: the reading-budget replay (W1, W2) before and after, alternating copies; the result is reported as measured, including when it shows no difference.

## Steps

1. `markDisplayed` (#249): this PR. The refetch, the revision, the architecture rule.
2. `setRead`, `setStar` (keys `m`, `s`): the same path, if step 1 holds.
3. The refresh batch (#303): merges in a small context, one refetch per batch; separate measurements at 200, 1,000 and 2,000 feeds.
