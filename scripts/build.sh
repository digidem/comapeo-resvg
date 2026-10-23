#!/usr/bin/env bash
# Builds prebuilds/<target>/comapeo-resvg.node and checks that it exports the
# N-API entry point and, on mobile, links against the nodejs-mobile runtime.
#
# Usage: scripts/build.sh <target>
#   target: ios-arm64 | ios-arm64-simulator | android-arm64 | android-arm | android-x64 | host

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$REPO/vendor-runtime"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/27.2.12479018}"
# A global RUSTFLAGS would replace the per-target link flags below.
unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS

TARGET="${1:?usage: $0 <target>}"
case "$TARGET" in
  ios-arm64)           TRIPLE=aarch64-apple-ios;       SLICE=ios-arm64 ;;
  ios-arm64-simulator) TRIPLE=aarch64-apple-ios-sim;   SLICE=ios-arm64-simulator ;;
  android-arm64)       TRIPLE=aarch64-linux-android;   ABI=arm64-v8a ;;
  android-arm)         TRIPLE=armv7-linux-androideabi; ABI=armeabi-v7a ;;
  android-x64)         TRIPLE=x86_64-linux-android;    ABI=x86_64 ;;
  # Named like node-gyp-build's prebuilds/<platform>-<arch> so the package loads in plain Node.
  host)                TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
                       TARGET="$(node -p 'process.platform + "-" + process.arch')" ;;
  *) echo "unknown target: $TARGET" >&2; exit 1 ;;
esac
RUSTFLAGS_VAR="CARGO_TARGET_$(echo "$TRIPLE" | tr 'a-z-' 'A-Z_')_RUSTFLAGS"

cd "$REPO"
case "$TARGET" in
  ios-*)
    FW_DIR="$RUNTIME/ios/NodeMobile.xcframework/$SLICE"
    [ -d "$FW_DIR" ] || { echo "missing $FW_DIR — run scripts/fetch-runtime.sh ios" >&2; exit 1; }
    # NodeMobile is built for iOS 14; napi-rs leaves napi_* to be resolved by a real link.
    export IPHONEOS_DEPLOYMENT_TARGET=14.0
    export "$RUSTFLAGS_VAR=-C link-arg=-F$FW_DIR -C link-arg=-framework -C link-arg=NodeMobile"
    cargo build --release --locked --target "$TRIPLE"
    LIB="target/$TRIPLE/release/libcomapeo_resvg.dylib"
    ;;
  android-*)
    LIBNODE_DIR="$RUNTIME/android/bin/$ABI"
    [ -f "$LIBNODE_DIR/libnode.so" ] || { echo "missing $LIBNODE_DIR/libnode.so — run scripts/fetch-runtime.sh android" >&2; exit 1; }
    # Bionic's linker namespaces need an explicit DT_NEEDED libnode.so, and
    # Android 15 needs 16 KB pages, which NDK r27 doesn't default to.
    export "$RUSTFLAGS_VAR=-L native=$LIBNODE_DIR -l node -C link-arg=-Wl,-z,max-page-size=16384"
    # API 24 is nodejs-mobile's floor and avoids RELR relocations older loaders can't read.
    cargo ndk -t "$ABI" --platform 24 build --release --locked
    LIB="target/$TRIPLE/release/libcomapeo_resvg.so"
    ;;
  *)
    cargo build --release --locked
    case "$TARGET" in
      darwin-*) LIB=target/release/libcomapeo_resvg.dylib ;;
      win32-*)  LIB=target/release/comapeo_resvg.dll ;;
      *)        LIB=target/release/libcomapeo_resvg.so ;;
    esac
    ;;
esac

OUT="prebuilds/$TARGET/comapeo-resvg.node"
rm -rf "prebuilds/$TARGET"
mkdir -p "prebuilds/$TARGET"
cp "$LIB" "$OUT"

fail() { echo "FAIL: $OUT $1" >&2; exit 1; }
case "$TARGET" in
  ios-*)
    # Rust leaves an absolute target/ path as the install name.
    install_name_tool -id @rpath/comapeo-resvg.node "$OUT"
    otool -L "$OUT" | grep -q 'NodeMobile\.framework/NodeMobile' || fail "does not link NodeMobile"
    [ "$TARGET" = ios-arm64 ] && PLATFORM=IOS || PLATFORM=IOSSIMULATOR
    xcrun vtool -show-build "$OUT" | grep -q "platform $PLATFORM$" || fail "is not built for $PLATFORM"
    nm -gU "$OUT" | grep -q ' _napi_register_module_v1$' || fail "does not export napi_register_module_v1"
    ;;
  android-*)
    READELF="$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-readelf)"
    "$READELF" -d "$OUT" | grep -q 'NEEDED.*libnode\.so' || fail "does not need libnode.so"
    "$READELF" -lW "$OUT" | awk '$1=="LOAD" && $NF!="0x4000"{bad=1} END{exit bad}' || fail "has a segment not 16 KB-aligned"
    "$READELF" --dyn-syms -W "$OUT" | grep -q napi_register_module_v1 || fail "does not export napi_register_module_v1"
    ;;
esac
echo "OK: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
