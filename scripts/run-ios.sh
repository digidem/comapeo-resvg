#!/usr/bin/env bash
# Runs the assembled nodejs-project on an iOS simulator with the harness from
# nodejs-mobile-bare-prebuilds, copied into .harness/.
#
# Usage: scripts/run-ios.sh [simulator-name-or-udid]
#   default: newest available "iPhone 17 Pro"

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_REPO="${HARNESS_REPO:-$REPO/../nodejs-mobile-bare-prebuilds}"
PROJECT="$REPO/nodejs-project"
BUNDLE_ID=com.digidem.nodejstest

SIM="${1:-iPhone 17 Pro}"

WORKSPACE="$REPO/.harness"
APP_DIR="$WORKSPACE/.nodejs-mobile-bare-prebuilds/test-harness/ios"
mkdir -p "$WORKSPACE/.nodejs-mobile-bare-prebuilds/test-harness"
rsync -a --delete \
  --exclude 'build/' --exclude 'DerivedData/' \
  --exclude 'NodeMobile/' --exclude 'nodejs-project/' \
  "$HARNESS_REPO/test-harness/ios/" "$APP_DIR/"

echo "== populating harness"
mkdir -p "$APP_DIR/NodeMobile"
rsync -a --delete "$REPO/vendor-runtime/ios/NodeMobile.xcframework/" \
  "$APP_DIR/NodeMobile/NodeMobile.xcframework/"
rsync -a --delete "$PROJECT/" "$APP_DIR/nodejs-project/"

echo "== building TestHarness.app"
(cd "$APP_DIR" && xcodebuild \
  -project TestHarness.xcodeproj \
  -scheme TestHarness \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build)
APP="$(find "$APP_DIR/build/Build/Products" -maxdepth 3 -name 'TestHarness.app' | head -1)"
[ -n "$APP" ] || { echo "TestHarness.app not found" >&2; exit 1; }
echo "== app: $APP"

# Accept either a UDID or a device name; for a name, take the newest runtime.
if [[ "$SIM" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  UDID="$SIM"
else
  UDID="$(xcrun simctl list devices available -j | SIM_NAME="$SIM" node -e '
const { devices } = JSON.parse(require("fs").readFileSync(0, "utf8"))
const version = (rt) => rt.replace(/.*-(\d+)-(\d+)$/, (_, a, b) => a.padStart(3, "0") + b.padStart(3, "0"))
const picks = Object.entries(devices)
  .flatMap(([rt, devs]) => devs.filter((d) => d.name === process.env.SIM_NAME).map((d) => [version(rt), d.udid]))
  .sort()
if (!picks.length) { console.error("no available simulator named " + process.env.SIM_NAME); process.exit(1) }
console.log(picks.at(-1)[1])
')"
fi
echo "== simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

xcrun simctl install "$UDID" "$APP"

EXIT_FILE="$WORKSPACE/ios-node-exit"
: > "$EXIT_FILE"
echo "== running test"
set +e
# --console-pty attaches a pty to the app's stdout and blocks until the app
# terminates; awk stops the pipe as soon as the sentinel appears.
xcrun simctl launch --console-pty --terminate-running-process \
  "$UDID" "$BUNDLE_ID" 2>&1 | awk -v out="$EXIT_FILE" '
  { print }
  /__NODE_EXIT__:/ {
    if (match($0, /__NODE_EXIT__:-?[0-9]+/)) {
      s = substr($0, RSTART, RLENGTH); sub(/^__NODE_EXIT__:/, "", s)
      print "NODE_EXIT_CODE=" s > out; close(out); exit
    }
  }'
set -e

[ -s "$EXIT_FILE" ] || { echo "FAIL: no __NODE_EXIT__ sentinel observed" >&2; exit 1; }
# shellcheck disable=SC1090
. "$EXIT_FILE"
echo "== node exited with code $NODE_EXIT_CODE"
exit "$NODE_EXIT_CODE"
