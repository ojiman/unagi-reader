#!/usr/bin/env bash
# Control-flow tests for scripts/check-test-log.sh, with small synthetic logs. Needs only bash.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
check="$here/check-test-log.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect_status() { # name expected-status log-file [xunit-file]
  local name=$1 expected=$2 log=$3
  bash "$check" "$log" ${4:+"$4"} >"$work/out" 2>&1; local status=$?
  if [ "$status" -eq "$expected" ]; then echo "ok   $name"; else echo "FAIL $name: expected exit $expected, got $status"; sed 's/^/     /' "$work/out"; failures=$((failures + 1)); fi
}
expect_message() { # name text (in the output of the last check)
  if grep -qF -- "$2" "$work/out"; then echo "ok   $1"; else echo "FAIL $1: the output has no '$2'"; sed 's/^/     /' "$work/out"; failures=$((failures + 1)); fi
}

begin='◇ Test run started.
↳ Testing Library Version: 2084
◇ Suite A started.'
a_start='◇ Test first() started.'
a_end='✔ Test first() passed after 0.010 seconds.'
b_start='◇ Test second() started.'
b_end='✔ Test second() passed after 0.020 seconds.'
cases_start='◇ Test sized(width:) started.
◇ Test case passing 1 argument width → 280.0 to sized(width:) started.
◇ Test case passing 1 argument width → 640.0 to sized(width:) started.'
cases_end='✔ Test sized(width:) with 2 test cases passed after 0.030 seconds.'
suite_end='✔ Suite A passed after 0.040 seconds.'
summary='✔ Test run with 3 tests in 1 suite passed after 0.040 seconds.'

printf '%s\n' "$begin" "$a_start" "$b_start" "$cases_start" "$a_end" "$b_end" "$cases_end" "$suite_end" "$summary" >"$work/clean.log"
expect_status "a finished run passes" 0 "$work/clean.log"

printf '%s\n' "$begin" "$a_start" "$b_start" "$a_end" >"$work/early.log"
expect_status "a run that stops early (no summary) fails" 1 "$work/early.log"
expect_message "  it says the summary is missing" "1 test run(s) started and 0"
expect_message "  it names the test that did not end" "second()"

printf '%s\n' "$begin" "$a_start" "$b_start" "$a_end" "$b_end" "$suite_end" "$summary" "$a_start" "◇ Test third() started." >"$work/after.log"
expect_status "a test that started and did not end fails even with a summary" 1 "$work/after.log"
expect_message "  it names it" "third()"

printf '%s\n' "$begin" "$a_start" "$a_end" "$suite_end" '✔ Test run with 1 test in 1 suite passed after 0.010 seconds.' "$begin" "$b_start" >"$work/second-run.log"
expect_status "a second run that stops early fails even though the first has a summary" 1 "$work/second-run.log"
expect_message "  it counts the runs" "2 test run(s) started and 1"

printf '%s\n' "$begin" "$a_start" "$a_end" "$suite_end" '✔ Test run with 1 test in 1 suite passed after 0.010 seconds.' "$begin" "$b_start" "$b_end" "$suite_end" '✔ Test run with 1 test in 1 suite passed after 0.010 seconds.' >"$work/two-runs.log"
expect_status "two finished runs pass" 0 "$work/two-runs.log"

printf '%s\n' "$begin" "$a_start" "$b_start" "$a_end" \
  '✘ Test second() recorded an issue at A.swift:9:5: Expectation failed: x == 1' \
  '✘ Test second() failed after 0.020 seconds with 1 issue.' \
  '✘ Suite A failed after 0.040 seconds with 1 issue.' \
  '✘ Test run with 2 tests in 1 suite failed after 0.040 seconds with 1 issue.' >"$work/failed.log"
expect_status "a failed test fails" 1 "$work/failed.log"
expect_message "  it shows the failure" "Expectation failed"

printf '%s\n' "$begin" "$a_start" "$a_end" '✘ Test run with 1 test in 1 suite failed after 0.010 seconds with 1 issue.' >"$work/failedrun.log"
expect_status "a failed run line alone fails" 1 "$work/failedrun.log"

printf '%s\n' "$begin" "$a_start" "$a_end" "$suite_end" '✔ Test run with 1 test in 1 suite passed after 0.010 seconds.' >"$work/singular.log"
expect_status "the singular summary ('1 test in 1 suite') passes" 0 "$work/singular.log"

: >"$work/empty.log"
expect_status "an empty log fails" 1 "$work/empty.log"
expect_status "a missing log fails" 1 "$work/does-not-exist.log"

printf '%s\n' "CoreData: error: something" "$begin" "$a_start" "swift: some other output" "$a_end" "$suite_end" "$summary" >"$work/noise.log"
expect_status "other output between the lines does not matter" 0 "$work/noise.log"

# With the xUnit file that Swift Testing writes itself (#186). The log below lost the end lines of first() and sized(width:).
xunit_case() { printf '        <testcase classname="T.A" name="%s" time="0.01"/>\n' "$1"; }
xunit_file() { # cases...
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<testsuites>' '    <testsuite name="TestResults" errors="0" tests="'$#'" failures="0" skipped="0" time="0.04">'
  for name in "$@"; do xunit_case "$name"; done
  printf '%s\n' '    </testsuite>' '</testsuites>'
}
printf '%s\n' "$begin" "$a_start" "$b_start" "$cases_start" "$b_end" "$suite_end" "$summary" >"$work/lost.log"
expect_status "lost end lines alone still fail" 1 "$work/lost.log"
xunit_file 'first()' 'second()' 'sized(width:)' >"$work/full.xml"
expect_status "lost end lines pass when the xUnit file lists the tests" 0 "$work/lost.log" "$work/full.xml"
expect_status "a missing xUnit file fails" 1 "$work/lost.log" "$work/missing.xml"
expect_message "  it says the run did not finish" "the run did not finish"
head -n 4 "$work/full.xml" >"$work/cut.xml"
expect_status "an xUnit file that is not closed fails" 1 "$work/lost.log" "$work/cut.xml"
xunit_file 'second()' 'sized(width:)' >"$work/short.xml"
expect_status "an xUnit file without a started test fails" 1 "$work/lost.log" "$work/short.xml"
expect_message "  it counts the cases against the summary" "2 test cases and the summary lines 3 tests"
expect_message "  it names the test" "first()"
sed 's|name="second()" time="0.01"/>|name="second()" time="0.01"><failure message="x"/></testcase>|' "$work/full.xml" >"$work/failure.xml"
expect_status "a failure in the xUnit file fails" 1 "$work/lost.log" "$work/failure.xml"
expect_status "a run that stops early fails with an xUnit file too" 1 "$work/early.log" "$work/full.xml"
xunit_file 'first()' 'second()' 'sized(width:)' 'skipped()' >"$work/skipped.xml"
printf '%s\n' "$begin" "$a_start" "$b_start" "$cases_start" "$suite_end" '✔ Test run with 4 tests in 1 suite passed after 0.040 seconds.' >"$work/skip.log"
expect_status "a skipped test counts as a test case, as in the summary" 0 "$work/skip.log" "$work/skipped.xml"

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
