#!/usr/bin/env bash
# Control-flow tests for scripts/ci-gate.sh. Needs only bash.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
gate="$here/ci-gate.sh"
failures=0

expect_value() { # name expected actual
  local name=$1 expected=$2 actual=$3
  if [ "$actual" = "$expected" ]; then echo "ok   $name"; else echo "FAIL $name: expected '$expected', got '$actual'"; failures=$((failures + 1)); fi
}
expect_status() { # name expected-status command...
  local name=$1 expected=$2; shift 2
  "$@" >/dev/null 2>&1; local status=$?
  if [ "$status" -eq "$expected" ]; then echo "ok   $name"; else echo "FAIL $name: expected exit $expected, got $status"; failures=$((failures + 1)); fi
}
classify() { printf '%s' "$1" | bash "$gate" classify; }

expect_value "docs only"                    false "$(classify $'docs/a.md\ndocs/decisions/b.md\n')"
expect_value "root markdown only"           false "$(classify $'README.md\nAGENTS.md\n')"
expect_value "any source file"              true  "$(classify $'docs/a.md\nSources/UnagiReader/ReaderView.swift\n')"
expect_value "workflow change is code"      true  "$(classify $'.github/workflows/ci.yml\n')"
expect_value "script change is code"        true  "$(classify $'scripts/build-app.sh\n')"
expect_value "non-docs file named like md"  true  "$(classify $'Sources/notes.txt\n')"
expect_value "empty list never skips"       true  "$(classify '')"
expect_value "blank lines only never skip"  true  "$(classify $'\n\n')"

packaging() { printf '%s' "$1" | bash "$gate" packaging; }
expect_value "packaging: build script"       true  "$(packaging $'scripts/build-app.sh\n')"
expect_value "packaging: package manifest"   true  "$(packaging $'Package.swift\nSources/a.swift\n')"
expect_value "packaging: workflow"           true  "$(packaging $'.github/workflows/ci.yml\n')"
expect_value "packaging: app icon"           true  "$(packaging $'Assets/AppIcon.icns\n')"
expect_value "packaging: notices"            true  "$(packaging $'ThirdPartyNotices.md\n')"
expect_value "packaging: plain source"       false "$(packaging $'Sources/UnagiReader/ReaderView.swift\nTests/a.swift\n')"
expect_value "packaging: empty list"         false "$(packaging '')"

# Local-only selection must not remove storage, editing or routing regressions.
local_tests=$(bash "$gate" local-tests)
expect_value "local-only list is nonempty" true "$([ -n "$local_tests" ] && echo true || echo false)"
local_only() { [[ "$1" =~ $local_tests ]] && echo true || echo false; }
expect_value "filter budget is local" true "$(local_only 'ReaderCoreTests.ArticleFilterStoreTests/tenThousandArticlesAreNarrowedQuickly()')"
expect_value "large import budget is local" true "$(local_only 'ReaderCoreTests.ImportFeedLookupTests/aFeedIsAddedQuicklyToALargeLibrary()')"
expect_value "line scan budget is local" true "$(local_only 'ReaderCoreTests.NoteLineStyleTests/aSixtyThousandLineNoteIsScannedQuickly()')"
expect_value "deadline elapsed-time bound is local" true "$(local_only 'ReaderCoreTests.DeadlineTests/anOperationThatIgnoresCancellationStillReleasesTheCallerAtTheDeadline()')"
expect_value "deadline semantics stay in CI" false "$(local_only 'ReaderCoreTests.DeadlineTests/cancellingTheCallerCancelsTheOperation()')"
expect_value "fold geometry is local" true "$(local_only 'ReaderUITests.SplitViewFoldTests/NoteBesideArticleTests/closingAnArrivingNoteReturnsTheList(width:)')"
expect_value "pixel heading is local" true "$(local_only 'ReaderUITests.ListHeaderTests/aLongTitleStaysInsideTheColumn()')"
expect_value "copy clock is local" true "$(local_only 'ReaderUITests.SplitViewFoldTests/MarkdownCopyTests/aCopyShowsACheckMarkForAMoment()')"
expect_value "large-note timing is local" true "$(local_only 'ReaderUITests.NoteTextEditorTests/aLargeNoteKeepsItsTextAndStaysQuick()')"
expect_value "store tests stay in CI" false "$(local_only 'ReaderCoreTests.NoteStoreTests/aFailedSaveKeepsTheNote()')"
expect_value "filter logic stays in CI" false "$(local_only 'ReaderCoreTests.ArticleFilterStoreTests/theFilterMatchesTheSummary()')"
expect_value "editor recovery stays in CI" false "$(local_only 'ReaderUITests.NoteTextEditorTests/aFailedSaveKeepsTheTypedTextInTheView()')"
expect_value "copy recovery stays in CI" false "$(local_only 'ReaderUITests.SplitViewFoldTests/MarkdownCopyTests/aFailedSaveCopiesTheVisibleNote(initial:)')"
expect_value "shortcut routing stays in CI" false "$(local_only 'ReaderUITests.OriginalKeyboardTests/nativeCommandsIgnoreModifiedInput()')"
expect_value "note typing routing stays in CI" false "$(local_only 'ReaderUITests.SplitViewFoldTests/TranslationTests/aTTypedInTheNoteRightAfterOpeningItIsWrittenNotTranslated(competingWindow:)')"
expect_value "article translation routing stays in CI" false "$(local_only 'ReaderUITests.SplitViewFoldTests/TranslationTests/aTWithTheKeyboardInTheArticleTranslates()')"
expect_value "note selection routing stays in CI" false "$(local_only 'ReaderUITests.SplitViewFoldTests/SendToNoteTests/theSelectionIsTheArticlesOnlyWhenTheArticleHasTheKeyboard()')"
expect_value "synthetic clock logic stays in CI" false "$(local_only 'ReaderUITests.ReaderPerformanceTests/theHeartbeatSubtractsItsExpectedTwentyMilliseconds()')"
expect_value "Sepia restoration logic stays in CI" false "$(local_only 'ReaderUITests.SplitViewFoldTests/FullScreenSepiaTests/changingTheDetachedWindowRestoresThePreviousWindow()')"

v() { bash "$gate" verdict "$@"; }
# docs only: both macOS jobs skipped
expect_status "docs only, jobs skipped"             0 v success false false pull_request skipped skipped
expect_status "docs only but regression ran"        1 v success false false pull_request success skipped
# a pull request that changes code but not packaging: regression only
expect_status "PR code, regression passed"          0 v success true false pull_request success skipped
expect_status "PR code, regression failed"          1 v success true false pull_request failure skipped
expect_status "PR code, regression cancelled"       1 v success true false pull_request cancelled skipped
expect_status "PR code, regression skipped"         1 v success true false pull_request skipped skipped
expect_status "PR code, release ran unexpectedly"   1 v success true false pull_request success success
# a pull request that changes packaging: both
expect_status "PR packaging, both passed"           0 v success true true pull_request success success
expect_status "PR packaging, release skipped"       1 v success true true pull_request success skipped
expect_status "PR packaging, release failed"        1 v success true true pull_request success failure
# push or manual run: release always
expect_status "push, both passed"                   0 v success true false push success success
expect_status "push, release skipped"               1 v success true false push success skipped
expect_status "manual run, release failed"          1 v success true false workflow_dispatch success failure
# the changes job itself
expect_status "changes job failed"                  1 v failure true false pull_request skipped skipped
expect_status "changes job cancelled"               1 v cancelled false false pull_request skipped skipped
expect_status "missing arguments"                   1 v success true
expect_status "unknown command"                     2 bash "$gate" nope

if [ "$failures" -ne 0 ]; then echo "$failures test(s) failed"; exit 1; fi
echo "all gate tests passed"
