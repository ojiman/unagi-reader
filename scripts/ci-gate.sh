#!/usr/bin/env bash
# Helpers for the `check` job in .github/workflows/ci.yml. The ruleset requires one status, `check`. It must report on
# every pull request, including documentation-only ones (where the macOS jobs are skipped) and failed or cancelled runs.
#
#   ci-gate.sh classify               Read changed file paths (one per line) from stdin. Print `true` when any path is
#                                     not documentation (docs/** or *.md), otherwise `false`. No input prints `true`,
#                                     so an empty or failed file list never skips the tests.
#   ci-gate.sh packaging              Read changed file paths from stdin. Print `true` when any path can change how the
#                                     app is built or packaged (see the case list below), otherwise `false`.
#   ci-gate.sh local-tests             Print the single --skip expression for local-only geometry/timing assertions.
#   ci-gate.sh verdict CHANGES CODE PACKAGING EVENT REGRESSION RELEASE
#                                     CHANGES = result of the `changes` job, CODE and PACKAGING = its outputs,
#                                     EVENT = the GitHub event name, REGRESSION and RELEASE = results of the two macOS jobs.
#                                     The release build runs on every push and manual run, and on a pull request only when it
#                                     changes the build or packaging. Exit 0 only when the pull request may merge.
set -euo pipefail

case "${1:-}" in
  classify)
    code=false; any=false
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      any=true
      case "$path" in
        docs/*|*.md) ;;
        *) code=true ;;
      esac
    done
    if [ "$any" = false ]; then code=true; fi
    echo "$code"
    ;;
  packaging)
    found=false
    while IFS= read -r path; do
      case "$path" in
        Package.swift|Package.resolved|ThirdPartyNotices.md|scripts/build-app.sh|Assets/*|.github/workflows/*) found=true ;;
      esac
    done
    echo "$found"
    ;;
  local-tests)
    # SwiftPM --skip patterns. Keep the tests; only macOS 27 runs these assertions.
    local_tests=(
      'ReaderCoreTests\.ArticleFilterStoreTests/tenThousandArticlesAreNarrowedQuickly' # 50 ms budget on the supported Mac.
      'ReaderCoreTests\.ImportFeedLookupTests/aFeedIsAddedQuicklyToALargeLibrary' # 1.5 s import budget.
      'ReaderCoreTests\.NoteLineStyleTests/aSixtyThousandLineNoteIsScannedQuickly' # 0.5 s scan budget.
      'ReaderCoreTests\.FirstRefreshPerformanceTests/firstRefreshAfterOPMLImport' # Opt-in refresh delay/RSS measurement.
      'ReaderCoreTests\.ExpiredRefreshPerformanceTests/' # Opt-in expired-content replay measurement.
      'ReaderCoreTests\.DeadlineTests/(aFastOperationReturnsAtOnceNotAtTheDeadline|anOperationThatIgnoresCancellationStillReleasesTheCallerAtTheDeadline)' # Elapsed-time bounds; timeout/cancellation outcome tests stay in CI.
      'ReaderUITests\.ArticleBandTests/' # Hosted control positions.
      'ReaderUITests\.ArticleTextSizeViewTests/' # Font layout and scroll positions.
      'ReaderUITests\.ListHeaderTests/' # Native text/pixel bounds.
      'ReaderUITests\.SidebarSectionHeaderTests/' # Hover pixels and positions.
      'ReaderUITests\.SidebarTitlebarTests/' # Native titlebar accessory geometry.
      'ReaderUITests\.SidebarRowTests/' # Hover pixels.
      'ReaderUITests\.FeedDragTests/aFolderRowShowsItIsTheTargetOnlyWhileADragIsOverIt' # Drop-target pixels.
      'ReaderUITests\.SplitViewFoldTests/ReaderLayoutTests/' # Folded column geometry.
      'ReaderUITests\.SplitViewFoldTests/SidebarButtonsTests/' # Mounted reader/fold control layout.
      'ReaderUITests\.SplitViewFoldTests/NoteBesideArticleTests/' # Animated width restoration.
      'ReaderUITests\.SplitViewFoldTests/NoteReaderTests/' # Hosted note/reader layout.
      'ReaderUITests\.SplitViewFoldTests/NotePanelTests/' # Inspector geometry.
      'ReaderUITests\.SplitViewFoldTests/SidebarBandTests/' # Heading/selection pixels.
      'ReaderUITests\.SplitViewFoldTests/FullScreenListTopTests/' # Native titlebar/list geometry.
      'ReaderUITests\.SplitViewFoldTests/FullScreenPresentationTests/completedExit' # Screen-constrained frame restoration.
      'ReaderUITests\.SplitViewFoldTests/MarkdownCopyTests/aCopyShowsACheckMarkForAMoment' # Tight real-time feedback interval (#388).
      'ReaderUITests\.SplitViewFoldTests/MarkdownCopyTests/theCopyButtonExistsAndAnEmptyNoteCannotBeCopied' # Mounted inspector controls.
      'ReaderUITests\.ListFilterTests/theFieldIsTheSystemSearchFieldOverTheList' # Native search-field bounds.
      'ReaderUITests\.ReaderSelectionRenderingTests/' # Hosted text-layout installation order.
      'ReaderUITests\.NoteTextEditorTests/aLargeNoteKeepsItsTextAndStaysQuick' # One-second editing budget.
      'ReaderUITests\.NoteInsertionTests/anInsertionIsShownWhereTheTextWent' # Native scroll-to-insertion geometry.
      'ReaderUITests\.NoteInsertionTests/forANoteThatOpensItIsShownAfterTheNoteHasComeIn' # Scroll after panel animation.
      'ReaderUITests\.NativeArticleTextTests/(pageMotion|fixedHero|paragraphPosition|viewportResize|headerOnlyViewport)' # Native layer/viewport geometry.
      'ReaderUITests\.NativeArticleListTests/(theTableFits|articleTextUsesSpace|aLongSourceName|rowsHaveRoom|backgroundInsertion|remountRestores|newArticles|manyNewArticles|whenTheReaderHasScrolled|reduceMotionFades|onlyInsertions|theTopOfTheList)' # Native row/scroll/animation geometry.
    )
    printf '%s\n' "${local_tests[@]}" | paste -sd '|' -
    ;;
  verdict)
    changes=${2:?changes result}; code=${3:?code output}; packaging=${4:?packaging output}
    event=${5:?event name}; regression=${6:?regression result}; release=${7:?release result}
    if [ "$changes" != success ]; then echo "check: the changes job ended with '$changes'" >&2; exit 1; fi
    if [ "$code" = false ]; then
      if [ "$regression:$release" = skipped:skipped ]; then echo "check: documentation only, macOS jobs skipped"; exit 0; fi
      echo "check: documentation only, but regression='$regression' release='$release'" >&2; exit 1
    fi
    if [ "$regression" != success ]; then echo "check: regression ended with '$regression'" >&2; exit 1; fi
    if [ "$event" != pull_request ] || [ "$packaging" = true ]; then wanted=success; else wanted=skipped; fi
    if [ "$release" != "$wanted" ]; then echo "check: release ended with '$release', expected '$wanted'" >&2; exit 1; fi
    echo "check: regression passed, release $release"
    ;;
  *)
    echo "usage: ci-gate.sh classify | packaging | local-tests | verdict CHANGES CODE PACKAGING EVENT REGRESSION RELEASE" >&2; exit 2
    ;;
esac
