# Reading budgets (issue #164)

Result: W1 PASS; W2 FAIL while reading, typing (one gap in two of three runs) and refreshing; W3 PASS (864–895 ms on a copy's second launch). These are measurements, not product acceptance. The budget values in specification 2.1 are unchanged; since 2026-10-19 W3 counts a copy's second and later launches.
Scope: main `91fc90c`, Release, ad hoc signed synthetic copies, macOS 27.0.1 (26A434), arm64 Mac14,2, Xcode 27.1 (27A9275), Swift 6.4, display at 60 Hz. Three copies on 2026-10-19 between 02:48 and 02:52 JST, each launched once and then for the replay; screen unlocked before and after every launch; no other build, test or Unagi Reader process.

| Budget | Measured result (copies 1 / 2 / 3) | Status |
|---|---|---|
| W1: p95 ≤ 100 ms, maximum ≤ 200 ms | 100 `j` / `k` events each; nearest-rank p95 73.818 / 72.947 / 72.648 ms; maximum 88.574 / 77.978 / 80.598 ms | PASS |
| W2: no scheduling delay over 100 ms | Reading: 32 / 36 / 36 gaps, longest 153.032 / 132.027 / 130.585 ms. Typing: 1 / 0 / 1 gaps, 119.754 and 102.606 ms. Refresh: 29 gaps each, 194–2,513 ms, sum 13.9 / 18.7 / 13.6 s | FAIL: [reading #249](https://github.com/ojiman/unagi-reader/issues/249); [typing #327](https://github.com/ojiman/unagi-reader/issues/327) (0 gaps in the earlier records); refresh with [#303](https://github.com/ojiman/unagi-reader/issues/303) (the refresh-batch work, the owner's decision of 2026-10-18 in #252) |
| W3: launch to list ≤ 1,000 ms, on a copy's second or later launch | 894.627 / 864.405 / 868.299 ms | PASS |
| A copy's first launch (no budget) | 1,787.6 / 1,191.0 / 1,296.8 ms | recorded only |

The previous record (2026-10-19, main `806776c`, before PR #324 removed the one-time discard of extracted bodies at launch) had W1 p95 85.454–86.117 ms, maximum 88.020–92.255 ms; W2 reading 85–92 gaps (longest 141.237 ms), typing 0, refresh 29 gaps of 183–1,489 ms; W3 1,084.747–1,136.219 ms on a copy's second launch. W2 varies between runs (the pane bounds were the same). With the demo library (`--seed-demo`, 6 articles) a later launch takes about 430 ms: the floor of SwiftUI and AppKit setup.

The replay uses a fresh copy of `BenchmarkFixtureTests`: 100 subscriptions, 10,000 articles, 80 Japanese paragraphs per body, with the fixture's links and quote formatting. The ordinary startup path runs with the fixture's source-less feeds. W1 is 51 `j` and 49 `k` events, including the initial selection; each must produce a display-start result before the next event, followed by a 300 ms pause. Typing inserts 64 committed ASCII characters through the actual note editor at 50 ms intervals and checks the saved text exactly. Note opening and setup are not W2 phases.

For refresh, setup assigns each synthetic feed its own URL and saves through the existing store path. In-memory HTTP responses then supply 100 existing entries per feed, through the ordinary parser and save/reload code. `readingBenchmarkComplete` requires that every feed finished without an error and the library still has 10,000 articles. Heartbeat counts were reading 1,454 / 1,450 / 1,449, typing 193 each and refresh 208 / 210 / 211.

The reported pane bounds, in points, are reading: sidebar 185, list 280, article 680, note 0; note open: sidebar 0, list 0, article 1,146, note 426, in all three replays. These are the helper's AppKit bounds readings, not assumed defaults or a measurement of visible pixels.

Raw output SHA-256, copies 1 to 3: `0b5a780736a9add763f4f7ca7ec40af9839fc035ee1e1de6b38528ce8a9a7b57`, `1033fb15d6d95f538ca79ac82cb8edf9d407a05d01639f6fc06f05a2e3d2ae90`, `6fad9b36ab91222f71d24055d46996d410183438353d21da1058a211b844e975`. Executed synthetic app's executable SHA-256: `0bae83bbfd21845d5cd6eb294165e9b83379fa56ca3a8ff5e01ca2523824a186`. Where the time went for W3 before PR #324 is in the comments of #250; for refresh, in #252.

The kernel timestamp is for this process only (`proc_pidinfo`, `PROC_PIDTBSDINFO`). W3 ends after the first visible, nonempty table draw, so it includes loading the store and process initialization. It excludes Launch Services work before process creation and does not measure the render server's first visible pixel. A newly made copy's first launch is slower than its later launches: about 250 ms with the demo library, 327–893 ms in the runs above; the cause is not established (possibly macOS checking a newly signed executable). A person meets it once after an install or an update, so W3 leaves it out. W1 keeps the existing meaning of display start: entry into installing the article's nonempty text, before all its layout has finished. W2 is a 20 ms main-actor heartbeat; it records interval minus 20 ms when that delay is over 100 ms. It is a scheduling-delay measurement, not a full thread trace or a motion-frame measurement.

## Note-typing follow-up (#327)

Result: the typing delay was not reproduced; its cause remains unknown. This does not clear the failures above or close [#327](https://github.com/ojiman/unagi-reader/issues/327). No save behavior changed.

On 2026-10-19, 05:24–05:28 JST, three full replays at main `ea9032f` used the unchanged recipe below. Same hardware, OS, toolchain, display and pane bounds as the scope above; Release, ad hoc signed synthetic copies, fresh fixture copies, screen unlocked, no other build, test or Unagi Reader process throughout. All three completed without an error, with 100 selection samples and all three heartbeat counts.

| Measurement | Copies 1 / 2 / 3 |
|---|---|
| Typing gaps over 100 ms | 0 / 0 / 0 (193 heartbeats each) |
| W1 p95 / maximum | 71.244 / 77.866 ms; 71.686 / 81.059 ms; 72.976 / 85.556 ms |
| W3, second launch | 804.072 / 793.246 / 786.055 ms |
| First launch (no budget) | 1,865.871 / 1,096.697 / 1,153.493 ms |
| Reading gaps / longest | 33 / 143.371 ms; 35 / 120.148 ms; 34 / 135.523 ms |
| Refresh gaps / longest | 29 / 543.413 ms; 29 / 525.895 ms; 29 / 495.598 ms |

W1 and W3 stayed within their limits; W2 still failed while reading and refreshing. These three short typing phases do not rule out an occasional slow save. Synchronous `saveNote` remains a hypothesis, not an established cause.

Output SHA-256, copies 1 to 3: `05ebbdd15a8397aae1301c5b418ae8e0da6b83d142306c294264be845a54b2c7`, `094aef6cba2252a2f0b2b572977c6fba018a5325ced22771a2f663b32d347fdb`, `b2b80da918158775a8cbb4f1c9a48cc49d85addcf1f3375c19e56b1459c774ca`. Executable SHA-256 (all three copies): `2bda701cba9bfd95b5d4cbae8cdd54c5051a1d21fe334652cb9d95ff78cb463f`.

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
