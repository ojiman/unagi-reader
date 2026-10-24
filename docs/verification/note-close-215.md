# Note closing (#215)

Result: the article-width regression passes, and the measured closing frame intervals improve. Ordinary packaged ESC, close-button and note editing checks pass.
Limit: the earliest divider-drag check fails; one observed mouse-down hit the table instead of the divider. Reliable earliest input remains under investigation in [#381](https://github.com/ojiman/unagi-reader/issues/381). This is not a complete smoke pass.
Scope: application source `7be3ba10d8c3e39456c27d783687e591c86e3903`, macOS 27.0.1 (26A434), Swift 6.4, Xcode 27.1, 60 Hz.

## Reproduction and regression checks

The new `closingTheNoteDoesNotSqueezeTheArticleBeforeTheListReturns` test failed before the fix at 1,240 pt: the article went from 939 pt to 492 pt before returning to 624 pt. It passes with the fix at 1,240 and 1,600 pt. Existing checks also preserve the window frame at 1,170/1,240 pt and exercise five rapid note open/close cycles at 1,240/1,600 pt.

At the source commit above:

- Full `swift test --scratch-path /private/tmp/unagi-reader-note215-tests`: UI 235 tests and core 357 tests completed without failure. Seven opt-in fixture/performance tests were skipped. `scripts/check-test-log.sh` confirmed completion.
- Related note, page and sidebar suites: 27 tests passed twice, with the log guard. The full run includes CI-excluded local checks.
- Release compilation, packaged catalog/version checks and the ZIP/signature round trip passed. The owner explicitly allowed the local ad hoc signatures; no Developer ID or distribution step was used.
- Fixed-commit static review found no required changes. The required CI `check` passed for this source commit.

## Synthetic Release measurement

A temporary driver based on `MotionBenchmark` sent five ESC key events through AppKit at each width, with one second between actions. It compared application source `31b6199` and the source commit above, using the same driver and six demo articles. Both copies had an explicit temporary library and synthetic bundle ID. No other build/test ran during these completed samples; the owner's ordinary app remained open.

The open note measured 426 pt in both variants. The closed layout measured a 185 pt sidebar and 280 pt list. These widths matched before and after at both window sizes; they are not the old 640 pt note baseline.

Each cell is the median / maximum of the longest display-link interval in each close, in ms:

| Window | Before | After |
|---|---:|---:|
| 1,600 pt | 88.8 / 211.0 | 30.1 / 34.2 |
| 1,170 pt | 33.3 / 122.0 | 21.8 / 30.3 |

The same 0.45 s observation window was retained, even though closing no longer requests a visible animation. These intervals measure main-thread display-link service, not input-to-pixel latency or render-server loss. Five samples are not a reading-budget guarantee. A long-fixture attempt did not complete and was discarded when later activity overlapped it; no long-note timing result is claimed.

## Packaged checks and limits

The focused `xcodebuild` run on the unmodified packaged source passed `testNoteCloseButtonAndEscape` and `testNoteLayoutKeepsEditing`, including layout changes, typing and restart. `testDividerDragAfterClosingNote` failed twice with a requested 340 pt and final 400 pt. Its application baseline passed 340 and 460 pt; see #381 for the input/resize observations. In a diagnostic repeat, mouse-down x=440.5 pt hit the table while the native divider was at x=720 pt. Restoration had ended about 0.405 s earlier; no 340 pt resize occurred. This failed attempt is not evidence of a width being overwritten. It does not rule out a race with a correctly targeted earlier drag.

The complete smoke was interrupted after its later fullscreen operation stopped progressing with infinite element coordinates. It is not a pass. Failed exploratory fixes were discarded; no native hierarchy mutations, pending close state, mouse monitor or diagnostic logging remain in the product change.

Not established: macOS 27.0, actual Japanese composition, VoiceOver, long use, long-note/image-heavy performance, or the earliest divider drag. Hosted input-method tests are logic evidence, not physical IME verification. The evidence-only CI rerun exposed an exact-width assertion in the mixed late-sidebar-fold test on macOS 26 (382 versus 400 pt); all state/focus checks were correct. The final test change keeps that logic in CI and moves its exact width/frame assertion into a separate local-only test, following architecture 5. Raw logs, traces and probe code stay outside the repository.
