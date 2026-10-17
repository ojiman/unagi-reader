# Expired-entry refresh

Result: PASS for the #287 removal/merge replay. This is not a full-refresh W2 pass.
Runtime commit: `8a47230536dd3d30b0c2a99852348f6927abdc38`; baseline: `f09c92870b0c4dd63964cd38e7cbe48db7ec4b22`.
Environment: 2026-10-18, macOS 27.0.1 (26A434), arm64, Xcode 27.1 (27A9275), Swift 6.4, Release.

## Replay

`ExpiredRefreshPerformanceTests` creates a temporary store with 200 feeds and 5,000 articles: 2,500 already-deleted expired entries, and 2,500 current snapshots with about 2 KiB each. It first replays the 2,500 single-ID `removeContent` calls of one refresh, then merges the 100 feeds that still carry those expired entries. Setup, saves and reloads are outside the timers. Before and after use the same fixture and test; each is a new process. No build, other test run or diagnostic sampling ran during these final samples.

| Main-actor work | Before | After |
| --- | ---: | ---: |
| Isolated removal calls, total | 60.521 s | 0.109 s |
| Expired-feed merges, total | 69.149 s | 2.414 s |
| Longest one-feed merge | 975.368 ms | 75.116 ms |

The 100 ms assertion on a single synchronous merge failed before the fix and passed after it. This catches an operation that alone exceeds W2; passing it does not prove W2 for a whole refresh. Batch save/reload, UI redraw and real-app input responsiveness are not measured here. #252 remains separate.

Run on the revision under test (Release):

```sh
UNAGI_READER_EXPIRED_REFRESH_BENCHMARK=1 swift test -c release --scratch-path /private/tmp/unagi-expired-refresh --filter ExpiredRefreshPerformanceTests > /private/tmp/unagi-expired-refresh.log 2>&1
bash scripts/check-test-log.sh /private/tmp/unagi-expired-refresh.log
```

The test is opt-in so a normal CI run does not acquire another wall-clock threshold. The ordinary retention tests also cover repeated removal, leftover bytes despite a deletion marker, unrelated content, one save per refresh batch, and rollback/retry after a failed save.

## Other checks and limits

- Local Debug run on the runtime tree above: 171 UI tests and a 292-test core summary, with the opt-in performance test disabled and three upgrade fixtures unset; the 10,000-article filter timing test was separated as in CI. Both test runs finished and passed `check-test-log.sh`; no `SWIFT TASK CONTINUATION MISUSE` diagnostic appeared.
- Release targeted run: 17 tests in three suites passed the log guard, including the enabled performance replay, retention and refresh-batch tests. The isolated Release replay passed separately.
- A second reviewer read the fixed runtime commit using `docs/review-checklist.md`, traced all removal callers, index freshness, batching and recovery, and found no actionable issue. The reviewer did not run tests and did not have enforced read-only isolation.
- macOS 26.6 / Swift 6.3.3 is left to PR CI. No real library, schema migration, network request, packaging change or new dependency. Japanese input, VoiceOver, Reduce Motion and long use were not checked.
