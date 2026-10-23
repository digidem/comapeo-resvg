#!/usr/bin/env bash
# Runs the assembled nodejs-project on an Android emulator or device with the
# harness from nodejs-mobile-bare-prebuilds, copied into .harness/ in the
# layout its run-test.sh expects (GITHUB_WORKSPACE=.harness).
#
# Usage: scripts/run-android.sh [abi] [avd]
#   abi: arm64-v8a (default) | x86_64 | armeabi-v7a
#   avd: name of an AVD to boot headless if no device is attached
#        (default Pixel_7a_API_34)
#   ANDROID_SERIAL picks the device when more than one is attached.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_REPO="${HARNESS_REPO:-$REPO/../nodejs-mobile-bare-prebuilds}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NODEJS_MOBILE_ANDROID="$REPO/vendor-runtime/android"
PROJECT="$REPO/nodejs-project"
command -v gradle >/dev/null || { echo "gradle not found on PATH" >&2; exit 1; }

ABI="${1:-arm64-v8a}"
AVD="${2:-Pixel_7a_API_34}"

export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

WORKSPACE="$REPO/.harness"
APP="$WORKSPACE/.nodejs-mobile-bare-prebuilds/test-harness/android"
mkdir -p "$WORKSPACE/.nodejs-mobile-bare-prebuilds/test-harness"
rsync -a --delete \
  --exclude 'app/build/' --exclude '.gradle/' --exclude 'app/libnode/' \
  --exclude 'app/src/main/assets/' \
  "$HARNESS_REPO/test-harness/android/" "$APP/"

echo "== populating harness ($ABI)"
mkdir -p "$APP/app/libnode/bin/$ABI" "$APP/app/src/main/assets"
rsync -a "$NODEJS_MOBILE_ANDROID/include/" "$APP/app/libnode/include/"
cp "$NODEJS_MOBILE_ANDROID/bin/$ABI/libnode.so" "$APP/app/libnode/bin/$ABI/libnode.so"
rm -rf "$APP/app/src/main/assets/nodejs-project"
rsync -a "$PROJECT/" "$APP/app/src/main/assets/nodejs-project/"

echo "== building apk"
(cd "$APP" && ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK" \
  gradle --no-daemon -PabiFilter="$ABI" :app:assembleDebug)
ls -l "$APP/app/build/outputs/apk/debug/app-debug.apk"

adb start-server >/dev/null 2>&1 || true
if [ -z "${ANDROID_SERIAL:-}" ]; then
  if [ -z "$(adb devices | awk 'NR>1 && $2=="device"{print $1}')" ]; then
    echo "== booting $AVD headless"
    nohup emulator -avd "$AVD" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect \
      >"$REPO/.harness/emulator.log" 2>&1 &
    adb wait-for-device
  fi
  # run-test.sh calls bare adb, which refuses to choose between several devices.
  ANDROID_SERIAL="$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
  export ANDROID_SERIAL
fi
adb shell 'while [ -z "$(getprop sys.boot_completed)" ]; do sleep 1; done'
echo "== device ready: $ANDROID_SERIAL ($(adb shell getprop ro.product.cpu.abi | tr -d '\r'))"

echo "== running test"
GITHUB_WORKSPACE="$WORKSPACE" "$APP/run-test.sh"
