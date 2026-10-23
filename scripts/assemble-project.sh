#!/usr/bin/env bash
# Builds the `nodejs-project/` tree the test harnesses copy into the app: this
# package with one prebuild, the icon fixtures, the harness's exit-sentinel
# main.js, test/test.js and pngjs, which it uses.
#
# Usage: [BENCH=1] scripts/assemble-project.sh <target> [dir]   (dir defaults to nodejs-project/)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_REPO="${HARNESS_REPO:-$REPO/../nodejs-mobile-bare-prebuilds}"
TARGET="${1:?usage: $0 <target> [dir]}"
PROJECT="${2:-$REPO/nodejs-project}"
PREBUILD="$REPO/prebuilds/$TARGET/comapeo-resvg.node"
[ -f "$PREBUILD" ] || { echo "missing $PREBUILD — run scripts/build.sh $TARGET" >&2; exit 1; }

# node-gyp-build looks in prebuilds/<platform>-<arch>/, and the simulator reports ios-arm64.
case "$TARGET" in
  ios-arm64-simulator) DIR=ios-arm64 ;;
  *)                   DIR="$TARGET" ;;
esac

rm -rf "$PROJECT"
PKG="$PROJECT/node_modules/comapeo-resvg"
mkdir -p "$PKG/prebuilds/$DIR"
cp "$REPO/package.json" "$REPO/index.js" "$PKG/"
cp "$PREBUILD" "$PKG/prebuilds/$DIR/"
cp -R "$REPO/node_modules/node-gyp-build" "$REPO/node_modules/pngjs" "$PROJECT/node_modules/"

echo '{ "name": "comapeo-resvg-test", "private": true, "main": "main.js" }' > "$PROJECT/package.json"
cp "$HARNESS_REPO/.github/actions/assemble-test-project/wrapper.js" "$PROJECT/main.js"
cp -R "$REPO/test/." "$PROJECT/"
# The harness runs test.js, so BENCH=1 puts the benchmark there instead.
[ -z "${BENCH:-}" ] || cp "$REPO/test/bench.js" "$PROJECT/test.js"

echo "== assembled $PROJECT for $TARGET"
