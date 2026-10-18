#!/usr/bin/env bash
# Reads the log of `swift test` (Swift Testing output) and fails when the run did not really finish, even if `swift test`
# exited with 0. It exists because a test process can end early with exit code 0 and no summary line (for example when a test
# stops the main run loop), and then CI shows a green job for tests that never ran.
#
#   check-test-log.sh LOGFILE [XUNIT]
#
# XUNIT is the file that Swift Testing writes itself with `swift test --xunit-output` (its name ends in `-swift-testing.xml`).
# CI's log can lose the end lines of fast tests although the tests passed (#186); a test that ended in the xUnit file counts as
# ended. The file is written when the run finishes, so a run that ended early has none, or an incomplete one.
#
# It fails when:
#   - the log is missing or empty;
#   - a run has no summary line "Test run with N tests ..." (the run ended early);
#   - a line starts with "✘" (a failed test, suite or run);
#   - a test was started and did not end ("◇ Test ... started." without "✔/✘ Test ... passed/failed after", nor, with XUNIT,
#     a test case of that name in the xUnit file);
#   - with XUNIT: the file is missing, empty or not closed; it has a failure; or its test cases do not add up to the tests of
#     the summary lines.
set -euo pipefail

log=${1:?usage: check-test-log.sh LOGFILE [XUNIT]}
xunit=${2:-}
if [ ! -s "$log" ]; then echo "check-test-log: '$log' is missing or empty" >&2; exit 1; fi

problems=0
fail() { echo "check-test-log: $1" >&2; problems=$((problems + 1)); }

# Every "Test run started." needs its own summary line: one `swift test` can start more than one run, and one of them can end early.
runs_started=$(grep -cE '^◇ Test run started\.$' "$log" || true)
runs_ended=$(grep -cE '^(✔|✘) Test run with [0-9]+ tests? in [0-9]+ suites? ' "$log" || true)
if [ "$runs_ended" -eq 0 ] || [ "$runs_ended" -ne "$runs_started" ]; then
  fail "$runs_started test run(s) started and $runs_ended 'Test run with ...' summary line(s): a test process ended before its run finished"
fi

xunit_names=""
if [ -n "$xunit" ]; then
  if [ ! -s "$xunit" ] || ! grep -q '</testsuites>' "$xunit"; then
    fail "the xUnit file '$xunit' is missing, empty or not closed: the run did not finish"
  else
    # One <testcase> element per line, as Swift Testing writes it; a skipped test is a test case too, as in the summary.
    summary_tests=$(grep -E '^(✔|✘) Test run with [0-9]+ tests? ' "$log" | sed -E 's/^.* Test run with ([0-9]+) tests? .*$/\1/' | awk '{ n += $1 } END { print n + 0 }')
    xunit_cases=$(grep -c '<testcase ' "$xunit" || true)
    if [ "$xunit_cases" -ne "$summary_tests" ]; then
      fail "the xUnit file has $xunit_cases test cases and the summary lines $summary_tests tests"
    fi
    if grep -qE '<(failure|error)[ >/]' "$xunit"; then fail "the xUnit file records a failure"; fi
    xunit_names=$(grep -o '<testcase [^>]*name="[^"]*"' "$xunit" | sed -E 's/.* name="([^"]*)"$/\1/' \
      | sed "s/&quot;/\"/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g" || true)
  fi
fi

failed=$(grep -E '^✘ ' "$log" || true)
if [ -n "$failed" ]; then
  fail "failures in the log:"
  printf '%s\n' "$failed" | head -n 20 >&2
fi

# Names of tests that started, and of those that ended. Lines about the run, a suite or one case of a parametrized test are not
# tests: a parametrized test prints one "Test case" line when each case starts, and one end line for the whole test.
started=$(grep -E '^◇ Test .* started\.$' "$log" | grep -vE '^◇ Test (run started\.|case )' \
  | sed -E 's/^◇ Test //; s/ started\.$//' | sort || true)
ended=$(grep -E '^(✔|✘) Test .* (passed|failed) after [0-9.]+ seconds' "$log" | grep -vE '^(✔|✘) Test run with ' \
  | sed -E 's/^(✔|✘) Test //; s/ (with [0-9]+ test cases )?(passed|failed) after [0-9.]+ seconds.*$//' | sort || true)
# The xUnit file lists every test of a finished run (checked against the summary above), so it replaces the log's end lines.
if [ -n "$xunit_names" ]; then ended=$(printf '%s\n' "$xunit_names" | sort); fi
unfinished=$(comm -23 <(printf '%s\n' "$started") <(printf '%s\n' "$ended") | grep -v '^$' || true)
if [ -n "$unfinished" ]; then
  fail "tests that started and did not end ($(printf '%s\n' "$unfinished" | wc -l | tr -d ' ')):"
  printf '%s\n' "$unfinished" | head -n 20 | sed 's/^/  /' >&2
fi

if [ "$problems" -ne 0 ]; then exit 1; fi
if [ -n "$xunit" ]; then
  echo "check-test-log: the run finished, with every started test ended (in the xUnit file) and no failure"
else
  echo "check-test-log: the run finished, with every started test ended and no failure"
fi
