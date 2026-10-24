#!/bin/bash
# Checks a release tag and prints its version (decision 0068).
#
#   release-version.sh TAG      for example `release-version.sh v1.0.0` prints `1.0.0`
#
# The tag is vX.Y.Z and points at HEAD, HEAD is on origin/main, and the history is complete, so the build number
# that scripts/build-app.sh counts is right.
set -euo pipefail
if [ $# -ne 1 ]; then echo "Usage: release-version.sh TAG" >&2; exit 2; fi
tag=$1
if ! [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then echo "release-version.sh: '$tag' is not vX.Y.Z" >&2; exit 2; fi
version=${BASH_REMATCH[1]}
if [ "$(git rev-parse --is-shallow-repository)" != false ]; then
    echo "release-version.sh: the clone is shallow; the build number needs the whole history" >&2; exit 1
fi
if ! tagged=$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}"); then echo "release-version.sh: no tag '$tag'" >&2; exit 1; fi
if [ "$tagged" != "$(git rev-parse HEAD)" ]; then echo "release-version.sh: '$tag' does not point at HEAD" >&2; exit 1; fi
if ! git merge-base --is-ancestor HEAD refs/remotes/origin/main 2>/dev/null; then
    echo "release-version.sh: HEAD is not on origin/main" >&2; exit 1
fi
echo "$version"
