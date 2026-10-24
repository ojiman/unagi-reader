#!/usr/bin/env bash
# Tests scripts/check-test-ran.sh with small synthetic xUnit files: a pass, a skip, a failure, a missing test, another suite of the same
# test name, a broken file and wrong arguments.
set -euo pipefail
cd "$(dirname "$0")/.."
script=scripts/check-test-ran.sh
failures=0
work=$(mktemp -d "${TMPDIR:-/tmp}/unagi-reader-test-check-test-ran.XXXXXX")
trap 'rm -rf "$work"' EXIT

xunit() {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites><testsuite name="TestResults" tests="2" failures="0" skipped="0">\n%s\n</testsuite></testsuites>\n' "$2" > "$work/$1"
}
expect_status() {
    local label=$1 wanted=$2; shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [ "$status" = "$wanted" ]; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s (exit %s, wanted %s)\n' "$label" "$status" "$wanted"; failures=$((failures + 1)); fi
}

suite=ReaderCoreTests.ReleaseStoreTests test='aLibraryWrittenByTheReleaseOpensAndKeepsEverything()'
xunit pass.xml "<testcase classname=\"$suite\" name=\"$test\" time=\"0.1\"/><testcase classname=\"Other\" name=\"other()\" time=\"0.1\"/>"
xunit skip.xml "<testcase classname=\"$suite\" name=\"$test\" time=\"0\"><skipped message=\"opt-in\"/></testcase>"
xunit fail.xml "<testcase classname=\"$suite\" name=\"$test\" time=\"0.1\"><failure message=\"lost\"/></testcase>"
xunit missing.xml "<testcase classname=\"Other\" name=\"other()\" time=\"0.1\"/>"
xunit other-suite.xml "<testcase classname=\"ReaderCoreTests.Other\" name=\"$test\" time=\"0.1\"/>"
printf '<testsuites><testsuite>' > "$work/broken.xml"

expect_status "a passed test" 0 bash "$script" "$work/pass.xml" "$suite" "$test"
expect_status "a skipped test" 1 bash "$script" "$work/skip.xml" "$suite" "$test"
expect_status "a failed test" 1 bash "$script" "$work/fail.xml" "$suite" "$test"
expect_status "a test that did not run" 1 bash "$script" "$work/missing.xml" "$suite" "$test"
expect_status "the same name in another suite" 1 bash "$script" "$work/other-suite.xml" "$suite" "$test"
expect_status "a broken file" 1 bash "$script" "$work/broken.xml" "$suite" "$test"
expect_status "a missing file" 1 bash "$script" "$work/none.xml" "$suite" "$test"
expect_status "too few arguments" 2 bash "$script" "$work/pass.xml" "$suite"

if [ "$failures" -ne 0 ]; then printf '%d check-test-ran test(s) failed\n' "$failures"; exit 1; fi
printf 'check-test-ran tests: OK\n'
