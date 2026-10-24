#!/bin/bash
# Tests scripts/release-version.sh in temporary Git repositories: a good tag prints its version; a bad name, a tag
# away from HEAD, a commit off main and a shallow clone are refused.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$PWD/scripts/release-version.sh"
failures=0
work=$(mktemp -d "${TMPDIR:-/tmp}/unagi-reader-test-release.XXXXXX")
trap 'rm -rf "$work"' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
# expect LABEL STATUS OUTPUT DIRECTORY TAG: run the script in DIRECTORY and compare its exit status and output.
expect() {
    local label=$1 wanted_status=$2 wanted_output=$3 directory=$4 tag=$5
    local status=0 output
    output=$(cd "$directory" && bash "$script" "$tag" 2> "$work/err.log") || status=$?
    if [ "$status" = "$wanted_status" ] && [ "$output" = "$wanted_output" ]; then pass "$label"
    else fail "$label (exit $status, output '$output'; wanted $wanted_status, '$wanted_output')"; cat "$work/err.log"; fi
}
g() { git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

repo="$work/repo"
g init -q "$repo"
g -C "$repo" commit -q --allow-empty -m one
g -C "$repo" commit -q --allow-empty -m two
g -C "$repo" update-ref refs/remotes/origin/main HEAD
g -C "$repo" tag v1.2.3
expect "a tag on HEAD and main gives its version" 0 1.2.3 "$repo" v1.2.3
expect "an annotated tag works too" 0 1.2.4 "$repo" "$(g -C "$repo" tag -a v1.2.4 -m 'v1.2.4' && echo v1.2.4)"
expect "a name without v is refused" 2 "" "$repo" 1.2.3
expect "a pre-release name is refused" 2 "" "$repo" v1.2.3-beta.1
expect "two numbers are refused" 2 "" "$repo" v1.2
expect "a missing tag is refused" 1 "" "$repo" v9.9.9

g -C "$repo" commit -q --allow-empty -m three
expect "a tag away from HEAD is refused" 1 "" "$repo" v1.2.3

g -C "$repo" tag v2.0.0
expect "a commit off origin/main is refused" 1 "" "$repo" v2.0.0
g -C "$repo" update-ref refs/remotes/origin/main HEAD
expect "the same commit on origin/main is accepted" 0 2.0.0 "$repo" v2.0.0

g clone -q --depth 1 --branch v2.0.0 "file://$repo" "$work/shallow" 2> /dev/null
g -C "$work/shallow" update-ref refs/remotes/origin/main HEAD
expect "a shallow clone is refused" 1 "" "$work/shallow" v2.0.0

if [ "$failures" -ne 0 ]; then printf '%d release-version test(s) failed\n' "$failures"; exit 1; fi
printf 'release-version tests: OK\n'
