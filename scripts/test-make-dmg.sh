#!/bin/bash
# Tests scripts/make-dmg.sh with a small synthetic app: the image holds the app and the /Applications link, the
# checksum matches, and bad input is refused without leaving an image. Needs macOS (codesign, hdiutil).
set -euo pipefail
cd "$(dirname "$0")/.."
make_dmg=scripts/make-dmg.sh
failures=0
work=$(mktemp -d /private/tmp/unagi-reader-test-dmg.XXXXXX)
trap 'if [ -d "$work/mount" ]; then hdiutil detach -quiet "$work/mount" 2>/dev/null || true; fi; rm -rf "$work"' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
expect_status() {
    local label=$1 wanted=$2; shift 2
    local status=0
    "$@" > "$work/out.log" 2>&1 || status=$?
    if [ "$status" = "$wanted" ]; then pass "$label"; else fail "$label (exit $status, wanted $wanted)"; cat "$work/out.log"; fi
}

app="$work/Synthetic Reader.app"
mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$app/Contents/MacOS/SyntheticReader"
chmod 755 "$app/Contents/MacOS/SyntheticReader"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SyntheticReader</string>
<key>CFBundleIdentifier</key><string>test.synthetic.reader</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"

image="$work/out/Synthetic-1.2.3.dmg"
expect_status "an image is made" 0 bash "$make_dmg" "$app" "$image"
if (cd "$work/out" && shasum -a 256 -c Synthetic-1.2.3.dmg.sha256 > /dev/null); then pass "the checksum matches"; else fail "the checksum matches"; fi
mkdir "$work/mount"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$work/mount" "$image"
if codesign --verify --deep --strict "$work/mount/Synthetic Reader.app"; then pass "the app inside is signed"; else fail "the app inside is signed"; fi
if [ "$(readlink "$work/mount/Applications")" = /Applications ]; then pass "the image links /Applications"; else fail "the image links /Applications"; fi
hdiutil detach -quiet "$work/mount"
rmdir "$work/mount"

expect_status "an existing image is not replaced" 1 bash "$make_dmg" "$app" "$image"
expect_status "the output must end in .dmg" 2 bash "$make_dmg" "$app" "$work/out/Synthetic.zip"
expect_status "a missing app is refused" 1 bash "$make_dmg" "$work/Missing.app" "$work/out/missing.dmg"
expect_status "two arguments are needed" 2 bash "$make_dmg" "$app"

# A file changed after signing breaks the signature: no image is made.
printf '#!/bin/sh\nexit 1\n' > "$app/Contents/MacOS/SyntheticReader"
expect_status "a broken signature is refused" 1 bash "$make_dmg" "$app" "$work/out/broken.dmg"
if [ ! -e "$work/out/broken.dmg" ]; then pass "no image is left for a broken app"; else fail "no image is left for a broken app"; fi

if [ "$failures" -ne 0 ]; then printf '%d make-dmg test(s) failed\n' "$failures"; exit 1; fi
printf 'make-dmg tests: OK\n'
