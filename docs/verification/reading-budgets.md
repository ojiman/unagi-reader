# Reading budgets (issue #164)

Result: W1 PASS; W2 FAIL while reading and refreshing; W3 FAIL. These are measurements, not product acceptance. The budgets in specification 2.1 are unchanged.
Scope: main `33d3dba` (after #283 and #286), Release, ad hoc signed synthetic copy, macOS 27.0.1 (26A434), arm64 Mac14,2, Xcode 27.1 (27A9275), Swift 6.4, display at 60 Hz. One replay on 2026-10-18 at 04:28, screen unlocked; no other build or test during it.

| Budget | Measured result | Status |
|---|---|---|
| W1: p95 ≤ 100 ms, maximum ≤ 200 ms | 100 `j` / `k` events; nearest-rank p95 71.699 ms; maximum 109.067 ms | PASS |
| W2: no scheduling delay over 100 ms | Reading: 53 gaps, longest 234.209 ms (all others 100–119 ms). Typing: 0 gaps. Refresh: 29 gaps of 454–889 ms, sum 18.9 s | FAIL: [reading #249](https://github.com/ojiman/unagi-reader/issues/249), [refresh #252](https://github.com/ojiman/unagi-reader/issues/252) |
| W3: launch to list ≤ 1,000 ms | 5,205.577 ms | FAIL: [#250](https://github.com/ojiman/unagi-reader/issues/250) |

The previous record (2026-10-17, main `8227159` plus instrumentation `2ef1f10`, before #283 and #286) had W1 p95 85.437 ms; W2 reading 24 gaps (longest 115.364 ms), typing 0, refresh **one gap of 308,883 ms**; W3 4,320.939 ms. The refresh batches of #286 turned the single five-minute stall into one stall per batch. The two runs are not a clean before/after for reading: the pane bounds differ (below), and W3 varies by several hundred milliseconds between runs (4,501 ms for an unrelated branch the same night).

The replay uses a fresh copy of `BenchmarkFixtureTests`: 100 subscriptions, 10,000 articles, 80 Japanese paragraphs per body, with the fixture's links and quote formatting. The ordinary startup path runs with the fixture's source-less feeds. W1 is 51 `j` and 49 `k` events, including the initial selection; each must produce a display-start result before the next event, followed by a 300 ms pause. Typing inserts 64 committed ASCII characters through the actual note editor at 50 ms intervals and checks the saved text exactly. Note opening and setup are not W2 phases.

For refresh, setup assigns each synthetic feed its own URL and saves through the existing store path. In-memory HTTP responses then supply 100 existing entries per feed, through the ordinary parser and save/reload code. `readingBenchmarkComplete` requires that every feed finished without an error and the library still has 10,000 articles. Heartbeat counts were reading 1,389, typing 191 and refresh 199.

The reported pane bounds, in points, are reading: sidebar 185, list 280, article 680, note 0; note open: sidebar 0, list 0, article 1,146, note 426 (the previous record: list 400, article 654; note open article 1,240, note 400). These are the helper's AppKit bounds readings, not assumed defaults or a measurement of visible pixels.

Raw output SHA-256: `08a850b9d32a3897d56ac619a6dc9a9c3c065ac886ec94a4d5ce02427fd90d75`. Executed synthetic app's executable SHA-256: `7c72184a65b1e2788caa86bfcbbffa6857948dedbfec46c976a6536397ceeb6f`. Where the time goes for W3 and refresh is in the comments of #250 and #252.

The kernel timestamp is for this process only (`proc_pidinfo`, `PROC_PIDTBSDINFO`). W3 ends after the first visible, nonempty table draw, so it includes loading the store and process initialization. It excludes Launch Services work before process creation and does not measure the render server's first visible pixel. W1 keeps the existing meaning of display start: entry into installing the article's nonempty text, before all its layout has finished. W2 is a 20 ms main-actor heartbeat; it records interval minus 20 ms when that delay is over 100 ms. It is a scheduling-delay measurement, not a full thread trace or a motion-frame measurement.

## Repeat

Build and export a new fixture, with the completion guard:

```sh
budget_fixture=$(mktemp -d /private/tmp/unagi-reader-budgets-fixture.XXXXXX)
budget_log=$(mktemp /private/tmp/unagi-reader-budgets-test.XXXXXX)
UNAGI_READER_BENCHMARK_DIRECTORY="$budget_fixture" swift test --scratch-path /private/tmp/unagi-reader-ci-build --force-resolved-versions --disable-keychain --disable-netrc --filter BenchmarkFixtureTests > "$budget_log" 2>&1 &&
    bash scripts/check-test-log.sh "$budget_log"
bash scripts/build-app.sh release
bash scripts/make-synthetic-copy.sh
```

Use the app path and new data directory printed by the last command. Copy the fixture into that empty directory with `ditto "$budget_fixture" <printed-data-directory>`. Replace `--seed-demo` in the printed launch command with `--performance-output <new-output.json> --reading-benchmark`, keeping `open -n -W` and `--data-directory`. Verify the process arguments and synthetic subscriptions as in AGENTS.md. The app performs the replay and quits; the full refresh can take several minutes. Start each repeat from a fresh fixture copy, because typing, read history and refresh change it. Keep the screen awake and unlocked: two runs made while the screen saver ran and the screen was locked (2026-10-18) had W1 p95 over 260 ms for an unchanged binary, and are not used.

Reject a missing file, a `readingBenchmarkError`, a false or missing `readingBenchmarkComplete`, anything other than 100 selection samples, a missing launch value, or missing reading/typing/refresh heartbeat counts. An empty or incomplete measurement is never a pass. For W1, sort the samples and use element `ceil(0.95 * count) - 1`; compare the maximum separately. For W2, check the aggregate and each phase's gaps, without averaging them away. For W3, compare `launchMilliseconds` to 1,000.

Not verified: other Macs, macOS 27.0 exactly, first launch after boot, Japanese input composition, VoiceOver, Reduce Motion variants, long use, live network timing, or CI performance. CI runs regression tests on macOS 26.6; it does not run the macOS 27 app or accept these budgets. No performance fix is included.
