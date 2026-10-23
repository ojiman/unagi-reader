# Local UI smoke restoration (#392)

PASS: the five functional smoke cases passed, with zero failures/skips, on local macOS 27.0.1.
OPEN: restored Sepia control-bar painting differs from ordinary entry; tracked in [#401](https://github.com/ojiman/unagi-reader/issues/401).

## Scope and environment

2026-10-24: macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Swift 6.4, arm64, 3840 × 2160 display. Synthetic bundle IDs and temporary libraries only; one GUI suite at a time. App sources match main `5c61cd8b1be075365888e02dbbe3477e1f9300b2`. The tested `UITests/UISmokeTests.swift` blob is `0b03e1e8e685e68d2965842722231e769bbdaa6a`.

## Cause and correction

A new library does not reset the OS scene's window state. The same UISmoke bundle also launched outside XCTest with View > Exit Full Screen, confirming genuine full screen rather than inferring it from a screen-sized frame. The original persistence sequence is not established; the faulty test assumption was that every launch would be a normal window.

Normal-window cases now reveal View and leave restored full screen through the native menu. The reading-key case deliberately quits/relaunches a full-screen Sepia scene and confirms restoration via the menu before normalizing it. Process-local keep-windows/theme arguments affect only the synthetic app. The [AppKit restoration guidance](https://developer.apple.com/documentation/AppKit/restoring-your-app-s-state-with-appkit) calls for normal quit; force quit discards saved state.

The recovered note-layout case exposed another fixture input error: its table was 265 pt wide while the scroll viewport was 280 pt. A visible scrollbar put the table-edge drag 16 pt before the real divider. It now drags the actual split-view divider; the 400 pt expectation and 3 pt tolerance are unchanged.

No app-source change, state deletion, global setting, automatic retry, fixed sleep or wider geometry tolerance was used. The native controls, both menu policies, five cases and nine ordinary exit/frame checks remain.

## Verification

- Baseline main `5c61cd8`: standard smoke 2 passed / 3 failed / 0 skipped (`/private/tmp/unagi-388-391-packaged/ui-smoke.xcresult`).
- RED: the normal-controls assertion failed on restored launch; the recovered note fixture failed at 280 pt versus 400 pt. An early async-setup assertion stalled XCTest teardown; normal-state checks now run in synchronous test bodies. A separate automation-mode initialization timeout did not run functional cases and is not a product result.
- GREEN: focused reading/full-screen and note-layout cases passed, then `CI_RESULTS=/private/tmp/unagi-392-final-five bash scripts/run-ui-smoke.sh` passed all five cases. The existing result checker accepted the xcresult summary. Build/test wall time was 292 s; the reading case took 104.932 s and the note-layout case 89.509 s, within the unchanged 120 s per-case bound.
- Release build and ad hoc signature, smoke support tests, documents check and diff check passed. Core/full hosted tests were not rerun locally for this test-only change.

Local logs, summary and xcresult are under `/private/tmp/unagi-392-final-five/`. No raw logs or probe code are committed.

## Restored Sepia and limits

Temporary native diagnostics, removed before the clean Release build, observed attachment with Sepia already active, `fullScreen=false`, and the cached close button still in the main window. It moved to the detached window on restored entry and the tint callback ran. This observed path did not attach with an already-detached button.

The captured restored bar was nevertheless neutral (RGB 237/236/235 at screen point 100/50), while ordinary entry was paper (242/236/218). Property assignments are not proof of final painting. #401 retains the reproduction and images; this PR does not fix that drawing difference.

macOS 27.0 exactly, physical display disconnection, Japanese input, VoiceOver, Reduce Motion and long use remain unverified. The formerly blocked 1000 × 650 gesture in #390 was reached successfully; its old macOS 26 cause remains unproven.
