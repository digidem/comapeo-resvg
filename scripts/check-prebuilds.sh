#!/usr/bin/env bash
# Fails unless prebuilds/ holds the addon for every target the package ships,
# so a missing CI artifact can't produce a package without it.
#
# Usage: scripts/check-prebuilds.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

missing=0
for target in darwin-arm64 darwin-x64 linux-x64 win32-x64 \
  ios-arm64 ios-arm64-simulator android-arm64 android-arm android-x64; do
  if [ ! -f "$REPO/prebuilds/$target/comapeo-resvg.node" ]; then
    echo "missing prebuilds/$target/comapeo-resvg.node" >&2
    missing=1
  fi
done
exit "$missing"
