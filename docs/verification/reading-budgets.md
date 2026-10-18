# Reading budgets (issue #164)

Result: W1 PASS; W2 FAIL while reading and refreshing; W3 FAIL (1,085–1,136 ms on a copy's second launch; most of the excess is a one-time cleanup that every fresh fixture copy runs, removed by [PR #324](https://github.com/ojiman/unagi-reader/pull/324)). These are measurements, not product acceptance. The budget values in specification 2.1 are unchanged; since 2026-10-19 W3 counts a copy's second and later launches.
Scope: main `806776c`, Release, ad hoc signed synthetic copies, macOS 27.0.1 (26A434), arm64 Mac14,2, Xcode 27.1 (27A9275), Swift 6.4, display at 60 Hz. Three copies on 2026-10-19 between 02:30 and 02:36 JST, each launched once and then for the replay; screen unlocked before and after every launch; no other build, test or Unagi Reader process.

| Budget | Measured result (copies 1 / 2 / 3) | Status |
|---|---|---|
| W1: p95 ≤ 100 ms, maximum ≤ 200 ms | 100 `j` / `k` events each; nearest-rank p95 85.471 / 85.454 / 86.117 ms; maximum 89.667 / 92.255 / 88.020 ms | PASS |
| W2: no scheduling delay over 100 ms | Reading: 85 / 92 / 86 gaps, longest 132.550 / 132.068 / 141.237 ms. Typing: 0 gaps. Refresh: 29 gaps each, 183–1,489 ms, sum 13.3 / 17.1 / 13.8 s | FAIL: [reading #249](https://github.com/ojiman/unagi-reader/issues/249); refresh with [#303](https://github.com/ojiman/unagi-reader/issues/303) (the refresh-batch work, the owner's decision of 2026-10-18 in #252) |
| W3: launch to list ≤ 1,000 ms, on a copy's second or later launch | 1,120.149 / 1,136.219 / 1,084.747 ms | FAIL: [#250](https://github.com/ojiman/unagi-reader/issues/250) |
| A copy's first launch (no budget) | 1,606.6 / 1,369.3 / 1,390.4 ms | recorded only |

Why W3 fails on main: the fixture has no `.extracted-bodies-discarded-v1` marker, and the marker belongs to the data directory, so every fresh fixture copy runs the one-time discard of extracted bodies (about 250 ms; [#250 comments](https://github.com/ojiman/unagi-reader/issues/250)). PR #324 removes that discard. With its build, plain launches 2 to 4 of one copy on one fixture copy took 845.5 / 886.4 / 869.0 ms; that is not yet a replay of this record. With the demo library (`--seed-demo`, 6 articles) the same build's later launches take about 430 ms: the floor of SwiftUI and AppKit setup.

The previous record (2026-10-18, main `33d3dba`) had W1 p95 71.699 ms, maximum 109.067 ms; W2 reading 53 gaps (longest 234.209 ms), typing 0, refresh 29 gaps of 454–889 ms; W3 5,205.577 ms. Its W3 was a copy's first launch, so it is not comparable with the W3 above. W2 varies between runs (the pane bounds were the same).

The replay uses a fresh copy of `BenchmarkFixtureTests`: 100 subscriptions, 10,000 articles, 80 Japanese paragraphs per body, with the fixture's links and quote formatting. The ordinary startup path runs with the fixture's source-less feeds. W1 is 51 `j` and 49 `k` events, including the initial selection; each must produce a display-start result before the next event, followed by a 300 ms pause. Typing inserts 64 committed ASCII characters through the actual note editor at 50 ms intervals and checks the saved text exactly. Note opening and setup are not W2 phases.

For refresh, setup assigns each synthetic feed its own URL and saves through the existing store path. In-memory HTTP responses then supply 100 existing entries per feed, through the ordinary parser and save/reload code. `readingBenchmarkComplete` requires that every feed finished without an error and the library still has 10,000 articles. Heartbeat counts were reading 1,437 / 1,446 / 1,459, typing 193 each and refresh 207 / 211 / 213.

The reported pane bounds, in points, are reading: sidebar 185, list 280, article 680, note 0; note open: sidebar 0, list 0, article 1,146, note 426, in all three replays. These are the helper's AppKit bounds readings, not assumed defaults or a measurement of visible pixels.

Raw output SHA-256, copies 1 to 3: `8fcfece220a7bc58df127f7fda53d4af7b354d9c423ad93c6a658bdda3862f92`, `ca48c16b0124aa112591d7ad20849f01a3f66e870460ab72cdaa4890e66ba886`, `61b8f0334690c7f416a5b4baf8415411005386884433c8e324030b774e5b9b23`. Executed synthetic app's executable SHA-256: `74ea0da43597945c63859314890192dbd1e1db09c9856469a1327631ddb1655d`. Where the time goes for W3 and refresh is in the comments of #250 and #252.

The kernel timestamp is for this process only (`proc_pidinfo`, `PROC_PIDTBSDINFO`). W3 ends after the first visible, nonempty table draw, so it includes loading the store and process initialization. It excludes Launch Services work before process creation and does not measure the render server's first visible pixel. A newly made copy's first launch is about 250 ms slower than its later launches, with either library; the cause is not established (possibly macOS checking a newly signed executable). A person meets it once after an install or an update, so W3 leaves it out. W1 keeps the existing meaning of display start: entry into installing the article's nonempty text, before all its layout has finished. W2 is a 20 ms main-actor heartbeat; it records interval minus 20 ms when that delay is over 100 ms. It is a scheduling-delay measurement, not a full thread trace or a motion-frame measurement.

## Repeat

Build and export a new fixture, with the completion guard:

```sh
budget_fixture=$(mktemp -d /private/tmp/unagi-reader-budgets-fixture.XXXXXX)
budget_log=$(mktemp /private/tmp/unagi-reader-budgets-test.XXXXXX)
UNAGI_READER_BENCHMARK_DIRECTORY="$budget_fixture" swift test --scratch-path /private/tmp/unagi-reader-ci-build --force-resolved-versions --disable-keychain --disable-netrc --filter BenchmarkFixtureTests >| "$budget_log" 2>&1 &&
    bash scripts/check-test-log.sh "$budget_log"
bash scripts/build-app.sh release
bash scripts/make-synthetic-copy.sh
```

Use the app path and new data directory printed by the last command. Each repeat has two launches of that same copy, each on its own fresh fixture copy:

1. **The copy's first launch** (recorded, no budget): `ditto "$budget_fixture" <printed-data-directory>`, then `open -n <app> --args --data-directory <printed-data-directory> --performance-output <first.json>`. When the file has `launchMilliseconds`, quit the app.
2. **The replay** (W1, W2 and W3): `ditto "$budget_fixture"` into another new, empty directory, then `open -n -W <app> --args --data-directory <that directory> --performance-output <replay.json> --reading-benchmark`. The app performs the replay and quits; the full refresh can take several minutes.

Verify the process arguments and synthetic subscriptions as in AGENTS.md. A new repeat needs a new copy (`make-synthetic-copy.sh` again) and new fixture copies, because typing, read history and refresh change the fixture. Keep the screen awake and unlocked: two runs made while the screen saver ran and the screen was locked (2026-10-18) had W1 p95 over 260 ms for an unchanged binary, and are not used.

Reject a missing file, a `readingBenchmarkError`, a false or missing `readingBenchmarkComplete`, anything other than 100 selection samples, a missing launch value, or missing reading/typing/refresh heartbeat counts. An empty or incomplete measurement is never a pass. For W1, sort the samples and use element `ceil(0.95 * count) - 1`; compare the maximum separately. For W2, check the aggregate and each phase's gaps, without averaging them away. For W3, compare the replay's `launchMilliseconds` to 1,000; report the first launch's value beside it.

Not verified: other Macs, macOS 27.0 exactly, first launch after boot, a Developer ID signed build (its first-launch check may cost a different amount), Japanese input composition, VoiceOver, Reduce Motion variants, long use, live network timing, or CI performance. CI runs regression tests on macOS 26.6; it does not run the macOS 27 app or accept these budgets. No performance fix is included.
