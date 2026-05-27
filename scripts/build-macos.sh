#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Paste}"
PRODUCT_NAME="${PRODUCT_NAME:-Paste}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-arm64}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Paste.entitlements"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-macos-$ARCH.zip"

cd "$ROOT_DIR"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$INFO_PLIST" "$ENTITLEMENTS" >/dev/null
fi

build_flags=(-c "$CONFIGURATION" --product "$PRODUCT_NAME" --arch "$ARCH")
bin_path_flags=(-c "$CONFIGURATION" --arch "$ARCH")

swift build "${build_flags[@]}"
BIN_DIR="$(swift build "${bin_path_flags[@]}" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Expected executable not found: $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ "${SKIP_CODESIGN:-0}" != "1" ]] && command -v codesign >/dev/null 2>&1; then
    identity="${CODESIGN_IDENTITY:--}"
    codesign_args=(--force --sign "$identity" --entitlements "$ENTITLEMENTS")
    if [[ "$identity" != "-" ]]; then
        codesign_args+=(--options runtime --timestamp)
    fi
    codesign "${codesign_args[@]}" "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
fi

if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
fi

echo "App bundle: $APP_BUNDLE"
if [[ -f "$ZIP_PATH" ]]; then
    echo "Zip package: $ZIP_PATH"
fi
