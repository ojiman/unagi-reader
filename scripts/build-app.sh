#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=${1:-debug}
case "$configuration" in debug|release) ;; *) echo "Usage: build-app.sh [debug|release]" >&2; exit 2 ;; esac
# A release (scripts/release-version.sh) sets UNAGI_READER_VERSION from its tag; any other build is 0.0.0.
version=${UNAGI_READER_VERSION:-0.0.0}
if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "build-app.sh: UNAGI_READER_VERSION '$version' is not X.Y.Z" >&2; exit 2; fi
# The build number is the count of commits, so it only grows. A shallow clone counts too few: a release refuses it.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
    build_number=$(git rev-list --count HEAD)
elif [ -n "${UNAGI_READER_VERSION:-}" ]; then
    echo "build-app.sh: a release needs the whole Git history for its build number" >&2; exit 2
else
    build_number=0
fi
if [ "$configuration" = release ]; then build_dir=/private/tmp/unagi-reader-v1-release; else build_dir=/private/tmp/unagi-reader-debug; fi
swift build -c "$configuration" --scratch-path "$build_dir"
binary_dir=$(swift build -c "$configuration" --scratch-path "$build_dir" --show-bin-path)
app_dir="$PWD/.build/Unagi Reader.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
# An executable left by an earlier build under another name would break the signature.
find "$app_dir/Contents/MacOS" -type f ! -name UnagiReader -delete
cp Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp ThirdPartyNotices.md "$app_dir/Contents/Resources/ThirdPartyNotices.md"
resource_bundle=UnagiReader_ReaderCore.bundle
rm -rf "$app_dir/Contents/Resources/$resource_bundle"
ditto "$binary_dir/$resource_bundle" "$app_dir/Contents/Resources/$resource_bundle"
# Replace the inode: overwriting an executable previously launched on macOS
# can retain stale kernel code-signature cache entries and terminate it with SIGKILL.
task_binary=$(mktemp "$app_dir/Contents/MacOS/UnagiReader.XXXXXX")
cp "$binary_dir/UnagiReader" "$task_binary"
chmod 755 "$task_binary"
mv -f "$task_binary" "$app_dir/Contents/MacOS/UnagiReader"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>UnagiReader</string>
<key>CFBundleIdentifier</key><string>xyz.ojima.UnagiReader</string>
<key>CFBundleName</key><string>Unagi Reader</string>
<key>CFBundleDisplayName</key><string>Unagi Reader</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# macOS must know the app's languages, not just the package resource bundle's languages. The version goes in here too.
python3 - "$app_dir/Contents/Info.plist" Sources/ReaderCore/Resources/Localizable.xcstrings "$version" "$build_number" <<'PYTHON'
import json, plistlib, sys
from pathlib import Path
info = Path(sys.argv[1])
catalog = json.loads(Path(sys.argv[2]).read_text())
version, build_number = sys.argv[3:5]
languages = {catalog["sourceLanguage"]}
for entry in catalog["strings"].values():
    languages.update(entry.get("localizations", {}))
plist = plistlib.loads(info.read_bytes())
plist["CFBundleLocalizations"] = sorted(languages)
plist["CFBundleShortVersionString"] = version
plist["CFBundleVersion"] = build_number
info.write_bytes(plistlib.dumps(plist))
PYTHON
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
# Retire the old build only after its replacement has a valid signature.
rm -rf "$PWD/.build/UnagiReader.app"
printf 'Built: %s\n' "$app_dir"
