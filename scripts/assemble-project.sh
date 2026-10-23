#!/usr/bin/env bash
# Builds the `nodejs-project/` tree that nodejs-mobile-test copies into the
# test app: this package with one prebuild, the icon fixtures, test/test.js,
# test/bench.js and pngjs, which they use.
#
# Usage: scripts/assemble-project.sh <target> [dir]   (dir defaults to nodejs-project/)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
PKG="$PROJECT/node_modules/@comapeo/resvg"
mkdir -p "$PKG/prebuilds/$DIR"
cp "$REPO/package.json" "$REPO/index.js" "$PKG/"
cp "$PREBUILD" "$PKG/prebuilds/$DIR/"
cp -R "$REPO/node_modules/node-gyp-build" "$REPO/node_modules/pngjs" "$PROJECT/node_modules/"

echo '{ "name": "comapeo-resvg-test", "private": true }' > "$PROJECT/package.json"
cp -R "$REPO/test/." "$PROJECT/"

echo "== assembled $PROJECT for $TARGET"
