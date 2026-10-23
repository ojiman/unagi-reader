#!/usr/bin/env bash
# Runs five real-app smoke tests. Build the app first; requires a logged-in macOS desktop and Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -le 1 ] || { echo "Usage: run-ui-smoke.sh [APP]" >&2; exit 2; }
source_app=${1:-"$PWD/.build/Unagi Reader.app"}
[ -f "$source_app/Contents/Info.plist" ] || { echo "Build the app first: bash scripts/build-app.sh" >&2; exit 1; }
run=$(mktemp -d "${TMPDIR:-/private/tmp}/unagi-ui-smoke.XXXXXX")
server_pid=''
smoke_domain=xyz.ojima.UnagiReader.Synthetic.UISmoke
language_set=false
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    if "$language_set"; then /usr/bin/defaults delete "$smoke_domain" AppleLanguages; fi
}
trap cleanup EXIT
# Use the checked helper; never launch the normal app or the person's library.
copy_output=$(bash scripts/make-synthetic-copy.sh "$source_app" "$run/data")
app=$(printf '%s\n' "$copy_output" | sed -n 's/^Ready: \(.*\) (synthetic bundle identifier, ad hoc signed)$/\1/p')
[ -n "$app" ] && [ "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = xyz.ojima.UnagiReader.Synthetic ]
# Separate from manual synthetic runs too. This temporary copy runs on the product support floor.
plutil -replace CFBundleIdentifier -string "$smoke_domain" "$app/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 27.0 "$app/Contents/Info.plist"
plutil -insert NSAppTransportSecurity -json '{"NSAllowsLocalNetworking":true}' "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
python3 UITests/serve.py "$run/feed-url" > "$run/server.log" 2>&1 &
server_pid=$!
for attempt in {1..50}; do
    [ ! -s "$run/feed-url" ] || break
    kill -0 "$server_pid" 2>/dev/null || { cat "$run/server.log" >&2; exit 1; }
    sleep 0.1
done
[ -s "$run/feed-url" ] || { echo "Local feed server did not start" >&2; exit 1; }
feed=$(cat "$run/feed-url")
results=${CI_RESULTS:-$run/results}
mkdir -p "$results"
echo "UI smoke logs and result bundle: $results"
# Keep label-based checks in English without changing the app's launch arguments.
[ "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = "$smoke_domain" ]
/usr/bin/defaults write "$smoke_domain" AppleLanguages -array en
language_set=true
[ "$(/usr/bin/defaults export "$smoke_domain" - | plutil -extract AppleLanguages.0 raw -o - -)" = en ]
started=$SECONDS
xcodebuild test -project UITests/UISmoke.xcodeproj -scheme UISmoke \
    -destination 'platform=macOS' -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
    -derivedDataPath "$run/build" -resultBundlePath "$results/ui-smoke.xcresult" \
    "UNAGI_UI_SMOKE_APP=$app" "UNAGI_UI_SMOKE_FEED=$feed" > "$results/ui-smoke.log" 2>&1 || {
        grep -E 'error:|Test Case .*failed' "$results/ui-smoke.log" >&2 || true
        tail -80 "$results/ui-smoke.log" >&2; exit 1;
    }
xcrun xcresulttool get test-results summary --path "$results/ui-smoke.xcresult" --compact > "$results/ui-smoke-summary.json"
python3 UITests/check_result.py "$results/ui-smoke-summary.json"
printf 'UI smoke build and test time: %s s\n' "$((SECONDS - started))" | tee "$results/ui-smoke-time.txt"
