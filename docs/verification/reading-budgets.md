# Reading budgets (issue #164)

Result: W1 PASS; W2 FAIL while reading and refreshing (no typing gaps in three replays); W3 PASS (791–823 ms on a copy's second launch). These are measurements, not product acceptance. The budget values in specification 2.1 are unchanged; since 2026-10-19 W3 counts a copy's second and later launches.
Scope: `b99a92d` (main `c93b978` plus the note-context fix `49637f3`), Release, ad hoc signed synthetic copies, macOS 27.0.1 (26A434), arm64 Mac14,2, Xcode 27.1 (27A9275), Swift 6.4, display at 60 Hz. Three copies on 2026-10-19 between 06:08 and 06:11 JST, each launched once and then for the replay; screen unlocked throughout; no other build, test or Unagi Reader process.

| Budget | Measured result (copies 1 / 2 / 3) | Status |
|---|---|---|
| W1: p95 ≤ 100 ms, maximum ≤ 200 ms | 100 `j` / `k` events each; nearest-rank p95 70.575 / 71.806 / 70.826 ms; maximum 75.520 / 81.392 / 81.851 ms | PASS |
| W2: no scheduling delay over 100 ms | Reading: 45 / 49 / 50 gaps, longest 135.255 / 124.393 / 126.747 ms. Typing: 0 gaps each. Refresh: 29 gaps each, 160–589 ms, sum 10.3 / 10.6 / 10.4 s | FAIL: [reading #249](https://github.com/ojiman/unagi-reader/issues/249); refresh with [#303](https://github.com/ojiman/unagi-reader/issues/303). The typing investigation is [#327](https://github.com/ojiman/unagi-reader/issues/327) |
| W3: launch to list ≤ 1,000 ms, on a copy's second or later launch | 812.716 / 823.234 / 791.193 ms | PASS |
| A copy's first launch (no budget) | 1,569.259 / 1,279.290 / 1,256.894 ms | recorded only |

The [previous record at main `91fc90c`](https://github.com/ojiman/unagi-reader/blob/ea9032fcfede564b9a750f0e01743afde7f1eb3a/docs/verification/reading-budgets.md) had typing gaps 1 / 0 / 1 (119.754 and 102.606 ms), reading gaps 32 / 36 / 36, and 29 refresh gaps each; W3 was 864.405–894.627 ms. Reading W2 varies between runs. The integrated replays above also include the view-chain and translation changes of #329 and #330, so they are not a controlled before/after comparison of reading or refresh. The paired typing diagnostic below keeps the UI identical.

The replay uses a fresh copy of `BenchmarkFixtureTests`: 100 subscriptions, 10,000 articles, 80 Japanese paragraphs per body, with the fixture's links and quote formatting. The ordinary startup path runs with the fixture's source-less feeds. W1 is 51 `j` and 49 `k` events, including the initial selection; each must produce a display-start result before the next event, followed by a 300 ms pause. Typing inserts 64 committed ASCII characters through the actual note editor at 50 ms intervals and checks the saved text exactly. Note opening and setup are not W2 phases. After each app quit, a read-only check of its temporary database confirmed the exact 64 characters persisted.

For refresh, setup assigns each synthetic feed its own URL and saves through the existing store path. In-memory HTTP responses then supply 100 existing entries per feed, through the ordinary parser and save/reload code. `readingBenchmarkComplete` requires that every feed finished without an error and the library still has 10,000 articles. Heartbeat counts were reading 1,390 / 1,393 / 1,395, typing 163 / 162 / 160 and refresh 209 / 202 / 203.

The reported pane bounds, in points, are reading: sidebar 185, list 280, article 680, note 0; note open: sidebar 0, list 0, article 1,146, note 426, in all three replays. These are the helper's AppKit bounds readings, not assumed defaults or a measurement of visible pixels.

Raw output SHA-256, copies 1 to 3: `1a2f2cb57c3f4fad7a14f6a32e1382a162d9c8cc06fcc4a20a1ac60602b7cec7`, `279a3c0009b75eb6acaa442057c2287520553fc58d80fdb7ca1a7ae1ef3ba22e`, `1659ffe88c619ba03f40b87de6fa6ae7352c875b676e45408344c45e8aa5b6d2`. Executed synthetic app's executable SHA-256: `1a955272903eac159e4e6ae4937fc9b72e12c7ebde267ba5adff6d6b5623229f`. Where the time went for W3 before PR #324 is in the comments of #250; for refresh, in #252.

The kernel timestamp is for this process only (`proc_pidinfo`, `PROC_PIDTBSDINFO`). W3 ends after the first visible, nonempty table draw, so it includes loading the store and process initialization. It excludes Launch Services work before process creation and does not measure the render server's first visible pixel. A copy's first launch is recorded separately; the cause of its extra cost is not established. W1 keeps the existing meaning of display start: entry into installing the article's nonempty text, before all its layout has finished. W2 is a 20 ms main-actor heartbeat; it records interval minus 20 ms when that delay is over 100 ms. It is a scheduling-delay measurement, not a full thread trace or a motion-frame measurement.

## Note-typing follow-up (#327)

The original 64-character typing phase did not reproduce the delay in three replays. An extended input diagnostic then reproduced long synchronous saves; a note-only context removed the measured typing gaps in the paired diagnostic. This is local evidence for [#327](https://github.com/ojiman/unagi-reader/issues/327), not general product acceptance.

On 2026-10-19, 05:24–05:28 JST, three full replays at main `ea9032f` used the unchanged recipe below. Same hardware, OS, toolchain, display and pane bounds as the scope above; Release, ad hoc signed synthetic copies, fresh fixture copies, screen unlocked, no other build, test or Unagi Reader process throughout. All three completed without an error, with 100 selection samples and all three heartbeat counts.

| Measurement | Copies 1 / 2 / 3 |
|---|---|
| Typing gaps over 100 ms | 0 / 0 / 0 (193 heartbeats each) |
| W1 p95 / maximum | 71.244 / 77.866 ms; 71.686 / 81.059 ms; 72.976 / 85.556 ms |
| W3, second launch | 804.072 / 793.246 / 786.055 ms |
| First launch (no budget) | 1,865.871 / 1,096.697 / 1,153.493 ms |
| Reading gaps / longest | 33 / 143.371 ms; 35 / 120.148 ms; 34 / 135.523 ms |
| Refresh gaps / longest | 29 / 543.413 ms; 29 / 525.895 ms; 29 / 495.598 ms |

W1 and W3 stayed within their limits; W2 still failed while reading and refreshing. These three short typing phases did not rule out an occasional slow save.

Output SHA-256, copies 1 to 3: `05ebbdd15a8397aae1301c5b418ae8e0da6b83d142306c294264be845a54b2c7`, `094aef6cba2252a2f0b2b572977c6fba018a5325ced22771a2f663b32d347fdb`, `b2b80da918158775a8cbb4f1c9a48cc49d85addcf1f3375c19e56b1459c774ca`. Executable SHA-256 (all three copies): `2bda701cba9bfd95b5d4cbae8cdd54c5051a1d21fe334652cb9d95ff78cb463f`.

### Extended input and the save path

A temporary Release diagnostic kept the 100 reading selections, then typed the same text at the same 50 ms intervals for 1,280 characters (20 times the normal typing phase). It recorded each complete `insertText` call and its `saveNote` call in memory, emitted the timings only after typing, checked the final text exactly, and quit before refresh. Both runs completed with 1,280 saves and inserts; read-only checks after quitting confirmed the exact 1,280 characters persisted in both temporary databases. This was a diagnostic, not a full W1–W3 replay. The temporary instrumentation was identical in both builds and is not included in the app.

Before: main `ea9032f`, 2026-10-19 05:42–05:45 JST. After: `49637f3` (the same UI plus the note-context fix), 06:02–06:04 JST. Same environment, fixture and pane bounds as above; screen unlocked and no other build, test or Unagi Reader process throughout each run.

| Measurement | Before | After |
|---|---:|---:|
| Typing gaps over 100 ms | 238; longest 245.681 ms | 0 |
| `saveNote` median / p95 / maximum | 37.527 / 58.985 / 207.221 ms | 2.694 / 3.382 / 13.495 ms |
| Complete insert median / p95 / maximum | 41.897 / 64.331 / 214.274 ms | 6.451 / 7.972 / 17.244 ms |
| Typing heartbeats | 2,956 | 3,206 |

A separate seven-second `sample` during typing at `ea9032f` with the same diagnostic found 1,707 of 3,031 main-thread samples in `ReaderStore.save` → SwiftData, including backing-data access for `Article` and `FeedMembership`. It supports isolating notes from the library's registered models. The sample adds overhead, so its timings are not used as budget evidence; it does not establish WAL checkpoints as the cause of the earlier short-phase outliers.

Diagnostic output SHA-256, before / after: `377696ea99a209c7877e5565a3180e21a983317a66473290c1196c047fd6a6b5` / `06dd70587021e60dc8f9b0cf0f4296c85b7a7a61218c1607e02d8a31f98cd4d6`. Executable SHA-256, before / after: `f14447cc513842c64f2e7474c933080f25dd26368deafb3aff58fd2d35bde127` / `7a7c978b472e32f935df7b962774eb718de36a21f10aec93b2885675e6530402`.

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

To measure other refreshes, add `--refresh-scenario unchanged`, `morning` or `typical` before `--reading-benchmark` (default `changed`, the replay above). `--reading-benchmark` must be the last argument: AppKit reads launch arguments in pairs, and an argument left without its pair is opened as a file, so the window never opens and the replay waits for ever (seen 2026-10-19/20). With a scenario, the app first refreshes once unmeasured to the stub's content, then measures a second refresh in which every feed answers that content again (`unchanged`), adds 10 new entries (`morning`), or answers 304 for 6 feeds in 10, the same content for 3 and 3 new entries for 1 (`typical`). The output names the scenario (`refreshScenario`). Verify the process arguments and synthetic subscriptions as in AGENTS.md. A new repeat needs a new copy (`make-synthetic-copy.sh` again) and new fixture copies, because typing, read history and refresh change the fixture. Keep the screen awake and unlocked: two runs made while the screen saver ran and the screen was locked (2026-10-18) had W1 p95 over 260 ms for an unchanged binary, and are not used.

Reject a missing file, a `readingBenchmarkError`, a false or missing `readingBenchmarkComplete`, anything other than 100 selection samples, a missing launch value, or missing reading/typing/refresh heartbeat counts. An empty or incomplete measurement is never a pass. For W1, sort the samples and use element `ceil(0.95 * count) - 1`; compare the maximum separately. For W2, check the aggregate and each phase's gaps, without averaging them away. For W3, compare the replay's `launchMilliseconds` to 1,000; report the first launch's value beside it.

Not verified: other Macs, macOS 27.0 exactly, first launch after boot, a Developer ID signed build (its first-launch check may cost a different amount), Japanese input composition, VoiceOver, Reduce Motion variants, long use, live network timing, or CI performance. CI runs regression tests on macOS 26.6; it does not run the macOS 27 app or accept these budgets.
