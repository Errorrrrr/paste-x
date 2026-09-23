#!/usr/bin/env bash
set -euo pipefail

# Fallback for hosts where SwiftPM cannot link Package.swift. Builds QA artifacts only.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_PATH="${SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="${ARCH:-arm64}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
SCRATCH_DIR="$(mktemp -d /tmp/pastex-direct-build-XXXXXX)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

compiler=(swiftc -sdk "$SDK_PATH" -target "$ARCH-apple-macosx14.0" -swift-version 6 -O)
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SCRATCH_DIR/clang-cache}"

compile_module() {
    local module="$1"
    shift
    mkdir -p "$SCRATCH_DIR/$module"
    (
        cd "$SCRATCH_DIR/$module"
        "${compiler[@]}" -emit-module -c -parse-as-library -module-name "$module" \
            -I "$SCRATCH_DIR" "$@" -emit-module-path "$SCRATCH_DIR/$module.swiftmodule"
    )
}

compile_module PasteCore "$ROOT_DIR"/Sources/PasteCore/*.swift
compile_module PasteMacSystem \
    "$ROOT_DIR"/Sources/PasteMacSystem/Clipboard/*.swift \
    "$ROOT_DIR"/Sources/PasteMacSystem/Paste/*.swift \
    "$ROOT_DIR"/Sources/PasteMacSystem/HotKey/*.swift \
    "$ROOT_DIR"/Sources/PasteMacSystem/Permissions/*.swift \
    "$ROOT_DIR"/Sources/PasteMacSystem/App/*.swift
compile_module PasteOverlay "$ROOT_DIR"/Sources/PasteOverlay/*.swift
compile_module PasteIntegration "$ROOT_DIR"/Sources/PasteIntegration/*.swift
compile_module PasteApp "$ROOT_DIR"/Sources/PasteApp/*.swift

"${compiler[@]}" "$SCRATCH_DIR"/{PasteCore,PasteMacSystem,PasteOverlay,PasteIntegration,PasteApp}/*.o \
    -o "$SCRATCH_DIR/PasteX"

APP_BUNDLE="$DIST_DIR/PasteX.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
ZIP_PATH="$DIST_DIR/PasteX-$VERSION-macos-$ARCH-qa-only.zip"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PasteXAppIcon.icns" "$APP_BUNDLE/Contents/Resources/PasteXAppIcon.icns"
cp "$SCRATCH_DIR/PasteX" "$APP_BUNDLE/Contents/MacOS/PasteX"
chmod 755 "$APP_BUNDLE/Contents/MacOS/PasteX"
codesign --force --sign - --entitlements "$ROOT_DIR/Resources/Paste.entitlements" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
echo "QA app: $APP_BUNDLE"
echo "QA archive: $ZIP_PATH"
