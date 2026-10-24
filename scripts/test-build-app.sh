#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:-"$PWD/.build/Unagi Reader.app"}
codesign --verify --deep --strict "$app"
python3 - "$app" Sources/ReaderCore/Resources/Localizable.xcstrings <<'PY'
import json, os, plistlib, sys
from pathlib import Path
app, catalog_path = map(Path, sys.argv[1:])
catalog = json.loads(catalog_path.read_text())
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
languages = set(next(iter(catalog["strings"].values()))["localizations"])
assert info["CFBundleDevelopmentRegion"] == "en"
expected_version = os.environ.get("UNAGI_READER_VERSION") or "0.0.0"
assert info["CFBundleShortVersionString"] == expected_version, ("version", info["CFBundleShortVersionString"], expected_version)
assert info["CFBundleVersion"].isdigit(), ("build number", info["CFBundleVersion"])
assert expected_version == "0.0.0" or int(info["CFBundleVersion"]) > 0, "a release has a build number"
assert set(info["CFBundleLocalizations"]) == languages
bundle = app / "Contents/Resources/UnagiReader_ReaderCore.bundle"
resources = bundle / "Contents/Resources" if (bundle / "Contents").exists() else bundle
for language in languages:
    directory = resources / (language + ".lproj")
    keys = set()
    for name in ["Localizable.strings", "Localizable.stringsdict"]:
        path = directory / name
        if path.exists():
            keys.update(plistlib.loads(path.read_bytes()))
    assert keys == set(catalog["strings"]), (language, "missing keys", set(catalog["strings"]) - keys)
print("Packaged UI languages, catalog coverage and version: OK")
PY
# The CI artifact must keep its resources and signature after downloading and extracting it.
roundtrip=$(mktemp -d /private/tmp/unagi-language-package.XXXXXX)
trap 'rm -rf "$roundtrip"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$roundtrip/app.zip"
ditto -x -k "$roundtrip/app.zip" "$roundtrip/extracted"
codesign --verify --deep --strict "$roundtrip/extracted/$(basename "$app")"
printf 'App ZIP/signature round-trip: OK\n'
