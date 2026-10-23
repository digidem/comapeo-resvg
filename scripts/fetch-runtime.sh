#!/usr/bin/env bash
# Downloads the digidem/nodejs-mobile release zips into vendor-runtime/
# (gitignored): the iOS zip carries NodeMobile.xcframework, the Android zip
# headers and bin/<abi>/libnode.so. The addon links against both.
#
# Usage: scripts/fetch-runtime.sh [ios|android|all]   (default: all)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODEJS_MOBILE_VERSION="${NODEJS_MOBILE_VERSION:-24.19.0-0}"

fetch() {
  local platform="$1"
  local url="https://github.com/digidem/nodejs-mobile/releases/download/v${NODEJS_MOBILE_VERSION}/nodejs-mobile-${platform}-${NODEJS_MOBILE_VERSION}.zip"
  local zip="$REPO/vendor-runtime/nodejs-mobile-${platform}-${NODEJS_MOBILE_VERSION}.zip"
  mkdir -p "$REPO/vendor-runtime"
  [ -f "$zip" ] || curl -fL --retry 3 -o "$zip" "$url"
  rm -rf "$REPO/vendor-runtime/$platform"
  unzip -q -o "$zip" -d "$REPO/vendor-runtime/$platform"
  echo "== $platform: $(ls "$REPO/vendor-runtime/$platform" | tr '\n' ' ')"
}

case "${1:-all}" in
  ios)     fetch ios ;;
  android) fetch android ;;
  all)     fetch ios; fetch android ;;
  *) echo "usage: $0 [ios|android|all]" >&2; exit 1 ;;
esac
