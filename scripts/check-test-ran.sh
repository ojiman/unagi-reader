#!/usr/bin/env bash
# Fails unless a named test ran and passed in a Swift Testing xUnit file. A required check that was skipped (an opt-in test
# whose input is missing) or did not run is never a pass (specification 7.1).
#
#   check-test-ran.sh XUNIT SUITE TEST     for example check-test-ran.sh tests-swift-testing.xml \
#                                              ReaderCoreTests.ReleaseStoreTests 'aLibraryWrittenByTheReleaseOpensAndKeepsEverything()'
set -euo pipefail
if [ $# -ne 3 ]; then echo "usage: check-test-ran.sh XUNIT SUITE TEST" >&2; exit 2; fi
python3 - "$@" <<'PY'
import sys
import xml.etree.ElementTree as ET
path, suite, test = sys.argv[1:]
try:
    root = ET.parse(path).getroot()
except (OSError, ET.ParseError) as error:
    sys.exit(f"check-test-ran: cannot read {path}: {error}")
cases = [case for case in root.iter("testcase") if case.get("classname") == suite and case.get("name") == test]
if not cases:
    sys.exit(f"check-test-ran: {suite}/{test} did not run")
for case in cases:
    for child in case:
        if child.tag in ("skipped", "failure", "error"):
            sys.exit(f"check-test-ran: {suite}/{test} was {child.tag if child.tag != 'error' else 'an error'}, not a pass")
print(f"check-test-ran: {suite}/{test} ran and passed")
PY
