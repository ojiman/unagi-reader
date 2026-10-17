# Refresh indexes after a large OPML import

Result: FAIL at 1,000 and 2,000 feeds; PASS at 200. Index reuse and incremental publication reduce the stalls and total refresh time, but do not meet the unchanged 100 ms budget at every scale. #303 remains open.

## Environment and method

Local: macOS 27.0.1 (26A434), arm64, Xcode 27.1 (27A9275), Swift 6.4. Baseline: `7411fb1e0121677f705d3cc889b7fa70e7c9c5f9` with temporary timing prints for index creation, merge, save and reload, and the 100 ms assertion. Timing prints are not shipped. Each scale uses a separate Release test process and a new temporary library. No builds or other test suites run during these measurements.

The fixture is unchanged: real OPML importer, FeedClient/parser and refresh controller, synthetic HTTP, 25 distinct articles per feed, roughly 2 KiB bodies. Import and setup are outside the refresh timer. The 10 ms heartbeat reports observed scheduling delay after subtracting its interval. This is not a real-window or render-server measurement. Peak RSS includes setup and the whole process.

```sh
UNAGI_READER_FIRST_REFRESH_FEEDS=200 swift test -c release \
  --scratch-path /private/tmp/unagi-303-before-build \
  --force-resolved-versions --disable-keychain --disable-netrc \
  --filter FirstRefreshPerformanceTests/firstRefreshAfterOPMLImport
# Repeat with 1000 and 2000, one process at a time; --skip-build after the first build.
```

## Before and after

| Feeds | Before refresh | Before longest delay | Before peak RSS | After refresh | After longest delay | After peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| 200 | 8.852 s | 242.817 ms: FAIL | 125.9 MiB | 5.663 s | 86.777 ms: PASS | 89.2 MiB |
| 1,000 | 162.123 s | 1,259.350 ms: FAIL | 334.4 MiB | 33.539 s | 237.543 ms: FAIL | 153.0 MiB |
| 2,000 | 630.810 s | 3,777.226 ms: FAIL | 592.4 MiB | 87.653 s | 740.553 ms: FAIL | 184.3 MiB |

The uninstrumented baseline at 200 feeds took 8.921 s with 232.303 ms longest delay, also FAIL. In the instrumented 1,000-feed run, the batch timings totalled 14.331 s for index creation, 6.632 s for merge, 11.161 s for save and 122.876 s for reload. These are synchronous main-actor intervals, not a sampling profile of the parser or UI.

A separate instrumented after run at 2,000 feeds took 85.607 s, with 320.926 ms longest delay (FAIL) and 226.5 MiB peak RSS. Across its 533 batches, index acquisition took 0.067 ms total, merge 16.898 s, save 34.288 s and publication 16.916 s. Its longest batch, at 48,650 articles, spent 32.804 ms in merge, 240.478 ms in save and 52.221 ms in publication. Reusing the lookup removes repeated index creation, but synchronous persistence and publication still exceed the budget. The largest observed gap varies between runs; neither after run establishes a 100 ms bound.

## Regression and acceptance

The focused Release run passed 27 tests in four suites (`RefreshIndexTests`, `RefreshBatchTests`, `ContentRetentionTests`, `ImportFeedLookupTests`), checked with `scripts/check-test-log.sh`. Expected injected save failures are logged; no continuation-misuse diagnostic was present. The full Release run finished 171 UI and 300 core tests; five opt-in tests were skipped (the first-refresh replay was run separately above). The separately timed filter test passed at 15.601 ms. Both logs passed the completion checker. No continuation-misuse diagnostic was present. Temporary-store CoreData I/O diagnostics also occur in the pre-change main CI and are tracked separately in #314; intentional corrupt-store/save-failure diagnostics remain. Pending: fixed-commit independent review, CI on Swift 6.3.3/macOS 26.6, and a synthetic packaged-app check. The core heartbeat cannot establish that reading and typing remain responsive in the app. Issue #303 stays open until the remaining failures and acceptance checks are resolved. Existing-library performance (#252), reading stalls (#249), launch (#250), Japanese input, VoiceOver and Reduce Motion are separate acceptance work.
