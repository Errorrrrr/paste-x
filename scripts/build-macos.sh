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

identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-${NOTARY_PROFILE:-}}"
release_temp_dir=""
release_succeeded=0

if [[ "$SIGNING_MODE" == "release" ]]; then
    if [[ "${SKIP_CODESIGN:-0}" == "1" ]]; then
        echo "Release builds require Developer ID codesigning; unset SKIP_CODESIGN." >&2
        exit 1
    fi
    if [[ -z "$identity" || "$identity" == "-" ]]; then
        echo "Release builds require CODESIGN_IDENTITY to be a Developer ID Application identity." >&2
        exit 1
    fi
    if [[ "$identity" != Developer\ ID\ Application:* ]]; then
        echo "Release builds require a Developer ID Application identity, got: $identity" >&2
        exit 1
    fi
    if [[ -z "$notary_profile" ]]; then
        echo "Release builds require NOTARY_KEYCHAIN_PROFILE for notarization." >&2
        exit 1
    fi
    if ! command -v codesign >/dev/null 2>&1; then
        echo "Release builds require codesign." >&2
        exit 1
    fi
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "Release builds require xcrun notarytool and stapler for notarization." >&2
        exit 1
    fi
    if ! command -v ditto >/dev/null 2>&1; then
        echo "Release builds require ditto to create the notarization zip." >&2
        exit 1
    fi
fi

cleanup_release_artifacts() {
    if [[ -n "$release_temp_dir" ]]; then
        rm -rf "$release_temp_dir"
    fi
    if [[ "$SIGNING_MODE" == "release" && "$release_succeeded" != "1" ]]; then
        rm -f "$ZIP_PATH"
    fi
}

if [[ "$SIGNING_MODE" == "release" ]]; then
    trap cleanup_release_artifacts EXIT
fi

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

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Signing mode: $SIGNING_MODE"

if [[ "${SKIP_CODESIGN:-0}" == "1" ]]; then
    echo "Skipping codesign; generated package is QA-only and not for distribution." >&2
elif command -v codesign >/dev/null 2>&1; then
    if [[ "$SIGNING_MODE" == "release" ]]; then
        identity="$identity"
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

create_zip() {
    local output_path="$1"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$output_path"
}

if [[ "$SIGNING_MODE" == "release" ]]; then
    release_temp_dir="$(mktemp -d "$DIST_DIR/$APP_NAME-notary.XXXXXX")"
    release_upload_zip="$release_temp_dir/$APP_NAME-macos-$ARCH-notary.zip"
    create_zip "$release_upload_zip"
    echo "Submitting release package for notarization with profile: $notary_profile"
    xcrun notarytool submit "$release_upload_zip" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$APP_BUNDLE"
    create_zip "$ZIP_PATH"
    release_succeeded=1
elif command -v ditto >/dev/null 2>&1; then
    create_zip "$ZIP_PATH"
fi

echo "App bundle: $APP_BUNDLE"
if [[ -f "$ZIP_PATH" ]]; then
    echo "Zip package: $ZIP_PATH"
fi
