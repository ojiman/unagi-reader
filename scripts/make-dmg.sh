#!/bin/bash
# Makes the disk image of a release (decision 0068): the app and a link to /Applications. It checks the app inside the
# mounted image and writes the image's SHA-256 to OUTPUT.sha256.
#
#   make-dmg.sh APP OUTPUT.dmg
#
# Only the system's hdiutil is used. An existing OUTPUT is never replaced.
set -euo pipefail
if [ $# -ne 2 ]; then echo "Usage: make-dmg.sh APP OUTPUT.dmg" >&2; exit 2; fi
app=$1 output=$2
case "$output" in *.dmg) ;; *) echo "make-dmg.sh: '$output' does not end in .dmg" >&2; exit 2 ;; esac
if [ ! -d "$app" ]; then echo "make-dmg.sh: no app at '$app'" >&2; exit 1; fi
if [ -e "$output" ] || [ -e "$output.sha256" ]; then echo "make-dmg.sh: '$output' or its .sha256 already exists" >&2; exit 1; fi
codesign --verify --deep --strict "$app"
name=$(basename "$app")
work=$(mktemp -d /private/tmp/unagi-reader-dmg.XXXXXX)
cleanup() {
    if [ -d "$work/mount" ]; then hdiutil detach -quiet "$work/mount" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/root"
ditto "$app" "$work/root/$name"
ln -s /Applications "$work/root/Applications"
hdiutil create -quiet -volname "Unagi Reader" -srcfolder "$work/root" -fs HFS+ -format UDZO "$work/image.dmg"
# Check the image as a person gets it: mounted read-only, the app still has a valid signature.
mkdir "$work/mount"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$work/mount" "$work/image.dmg"
codesign --verify --deep --strict "$work/mount/$name"
test "$(readlink "$work/mount/Applications")" = /Applications
hdiutil detach -quiet "$work/mount"
rmdir "$work/mount"
mkdir -p "$(dirname "$output")"
mv "$work/image.dmg" "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")") > "$output.sha256"
printf 'Made: %s\n' "$output"
cat "$output.sha256"
