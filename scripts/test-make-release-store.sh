#!/bin/bash
# Tests the refusals of scripts/make-release-store.sh: bad arguments, a directory outside /private/tmp/unagi-reader-*, an existing
# directory and a missing tag. Builds nothing; CI's regression job runs the script for real.
set -euo pipefail
cd "$(dirname "$0")/.."
script=scripts/make-release-store.sh
failures=0
existing=$(mktemp -d /private/tmp/unagi-reader-test-release-store.XXXXXX)
trap 'rm -rf "$existing"' EXIT
fresh=/private/tmp/unagi-reader-test-release-store-new-$$

expect_status() {
    local label=$1 wanted=$2; shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [ "$status" = "$wanted" ]; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s (exit %s, wanted %s)\n' "$label" "$status" "$wanted"; failures=$((failures + 1)); fi
}

expect_status "no arguments" 2 bash "$script"
expect_status "three arguments" 2 bash "$script" "$fresh" v1.0.0 extra
expect_status "a tag that is not vX.Y.Z" 2 bash "$script" "$fresh" main
expect_status "a directory outside /private/tmp" 1 bash "$script" "$HOME/unagi-reader-release-store" v1.0.0
expect_status "a /private/tmp directory with another name" 1 bash "$script" /private/tmp/release-store-$$ v1.0.0
expect_status "an existing directory" 1 bash "$script" "$existing" v1.0.0
expect_status "a tag that is not in this clone" 1 bash "$script" "$fresh" v0.0.999
if [ ! -e "$fresh" ]; then printf 'PASS %s\n' "no directory is left after a refusal"; else printf 'FAIL %s\n' "no directory is left after a refusal"; failures=$((failures + 1)); rm -rf "$fresh"; fi

if [ "$failures" -ne 0 ]; then printf '%d make-release-store test(s) failed\n' "$failures"; exit 1; fi
printf 'make-release-store tests: OK\n'
