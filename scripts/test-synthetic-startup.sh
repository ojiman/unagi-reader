#!/usr/bin/env bash
# Exercise the app's directory resolver in child processes. The normal library is a fixture, never HOME.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /private/tmp/unagi-startup-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.swift" <<'SWIFT'
import Foundation

let fixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_LIBRARY"]!, isDirectory: true)
do {
    let directory = try AppDataDirectory.resolve(arguments: CommandLine.arguments,
        bundleIdentifier: Bundle.main.bundleIdentifier, normalDirectory: fixture)
    // Stand in for the first store write, after the same resolver call as UnagiReaderApp.init.
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("opened\n".utf8).write(to: directory.appending(path: "opened"))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(64)
}
SWIFT
mkdir -p "$work/Startup.app/Contents/MacOS"
xcrun swiftc Sources/UnagiReader/AppDataDirectory.swift "$work/main.swift" -o "$work/Startup.app/Contents/MacOS/Startup"
python3 - "$work" <<'PY'
import os
from pathlib import Path
import subprocess
import plistlib
import sys

root = Path(sys.argv[1]).resolve()
library = root / "owner/Library/Application Support/UnagiReader"
library.mkdir(parents=True)
marker = library / "keep.txt"
marker.write_text("keep")
synthetic = "xyz.ojima.UnagiReader.Synthetic"

def run(args, *, bundle=synthetic, refused=True):
    contents = root / "Startup.app/Contents"
    info = {"CFBundleExecutable": "Startup", "CFBundlePackageType": "APPL"}
    if bundle:
        info["CFBundleIdentifier"] = bundle
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    result = subprocess.run([str(contents / "MacOS/Startup"), *args],
        env=dict(os.environ, TEST_LIBRARY=str(library)), text=True, capture_output=True, timeout=10)
    assert result.returncode == (64 if refused else 0), (args, bundle, result.returncode, result.stdout, result.stderr)
    if refused:
        assert "synthetic app" in result.stderr, result.stderr
    assert marker.read_text() == "keep"
    return result

for bundle in [synthetic, synthetic + ".UISmoke", synthetic + ".Probe"]:
    for args in [[], ["--seed-demo"], ["--data-directory"], ["--data-directory", ""],
                 ["--data-directory", "--seed-demo"], ["--data-directory", str(root / "ignored"), "--data-directory", str(library)]]:
        run(args, bundle=bundle)
assert list(library.iterdir()) == [marker]
print("ok   missing and malformed paths refused before any store write, including synthetic child IDs")

alias = root / "library-alias"
alias.symlink_to(library, target_is_directory=True)
for path in [library, library / "child", library / "../UnagiReader", alias, alias / "child", alias / "new/child", Path(os.path.relpath(library)),
             Path(str(library).upper()) / "child"]:
    run(["--data-directory", str(path)])
assert list(library.iterdir()) == [marker]
print("ok   normal library, descendants, normalized paths, case variants and symlink aliases refused")

safe = root / "explicit data with spaces"
run(["--data-directory", str(safe), "--seed-demo"], refused=False)
assert (safe / "opened").read_text() == "opened\n"
run(["--data-directory", str(safe)], bundle=synthetic + ".UISmoke", refused=False)
assert not (library / "opened").exists()
sibling = root / "owner/Library/Application Support/UnagiReader-extra"
run(["--data-directory", str(sibling)], refused=False)
assert (sibling / "opened").exists()
print("ok   helper and smoke argument shapes allow an explicit synthetic library and its restart")

for bundle in ["xyz.ojima.UnagiReader", synthetic + "Backup", ""]:
    run([], bundle=bundle, refused=False)
    assert (library / "opened").read_text() == "opened\n"
    (library / "opened").unlink()
run(["--data-directory", str(safe)], bundle="xyz.ojima.UnagiReader", refused=False)
print("ok   normal app defaults and explicit-directory behavior are unchanged; prefix boundary respected")
print("all passed")
PY
