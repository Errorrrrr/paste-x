#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Paste}"
PRODUCT_NAME="${PRODUCT_NAME:-Paste}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-arm64}"
SIGNING_MODE="${SIGNING_MODE:-qa}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Paste.entitlements"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

case "$SIGNING_MODE" in
    qa)
        ZIP_PATH="$DIST_DIR/$APP_NAME-macos-$ARCH-qa-only.zip"
        ;;
    release)
        ZIP_PATH="$DIST_DIR/$APP_NAME-macos-$ARCH.zip"
        ;;
    *)
        echo "SIGNING_MODE must be either 'qa' or 'release'." >&2
        exit 1
        ;;
esac

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

rm -rf "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-macos-$ARCH.zip" "$DIST_DIR/$APP_NAME-macos-$ARCH-qa-only.zip"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Signing mode: $SIGNING_MODE"

if [[ "${SKIP_CODESIGN:-0}" == "1" ]]; then
    if [[ "$SIGNING_MODE" == "release" ]]; then
        echo "Release builds require Developer ID codesigning; unset SKIP_CODESIGN." >&2
        exit 1
    fi
    echo "Skipping codesign; generated package is QA-only and not for distribution." >&2
elif command -v codesign >/dev/null 2>&1; then
    if [[ "$SIGNING_MODE" == "release" ]]; then
        identity="${CODESIGN_IDENTITY:-}"
        if [[ -z "$identity" || "$identity" == "-" ]]; then
            echo "Release builds require CODESIGN_IDENTITY to be a Developer ID Application identity." >&2
            exit 1
        fi
    else
        identity="${CODESIGN_IDENTITY:--}"
    fi

    codesign_args=(--force --sign "$identity" --entitlements "$ENTITLEMENTS")
    if [[ "$identity" != "-" ]]; then
        codesign_args+=(--options runtime --timestamp)
    fi
    codesign "${codesign_args[@]}" "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
else
    if [[ "$SIGNING_MODE" == "release" ]]; then
        echo "Release builds require codesign." >&2
        exit 1
    fi
    echo "codesign not found; generated package is QA-only and not for distribution." >&2
fi

if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
fi

echo "App bundle: $APP_BUNDLE"
if [[ -f "$ZIP_PATH" ]]; then
    echo "Zip package: $ZIP_PATH"
fi
