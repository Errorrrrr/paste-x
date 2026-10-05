#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 APP_BUNDLE DMG_PATH" >&2
    exit 1
fi

if [[ ! -d "$1" || ! -f "$1/Contents/Info.plist" || ! -d "$1/Contents/MacOS" ]]; then
    echo "Expected a macOS app bundle: $1" >&2
    exit 1
fi

for tool in ditto hdiutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Creating a macOS disk image requires $tool." >&2
        exit 1
    fi
done

APP_BUNDLE="$(cd "$1" && pwd -P)"
OUTPUT_NAME="$(basename "$2")"
case "$OUTPUT_NAME" in
    .dmg)
        echo "Expected a disk image filename ending in .dmg: $2" >&2
        exit 1
        ;;
    *.dmg) ;;
    *)
        echo "Expected a disk image filename ending in .dmg: $2" >&2
        exit 1
        ;;
esac

if [[ ! -d "$(dirname "$2")" ]]; then
    echo "The disk image output directory must already exist: $(dirname "$2")" >&2
    exit 1
fi
OUTPUT_DIR="$(cd "$(dirname "$2")" && pwd -P)"
DMG_PATH="$OUTPUT_DIR/$OUTPUT_NAME"
case "$DMG_PATH" in
    "$APP_BUNDLE"/*)
        echo "The disk image must be outside the app bundle." >&2
        exit 1
        ;;
esac
if [[ -e "$DMG_PATH" || -L "$DMG_PATH" ]]; then
    echo "Output already exists; remove the previous disk image first: $DMG_PATH" >&2
    exit 1
fi

WORK_DIR=""
IMAGE_DIR=""
cleanup() {
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    if [[ -n "$IMAGE_DIR" ]]; then
        rm -rf "$IMAGE_DIR"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pastex-dmg.XXXXXX")"
# Keep the image on the destination filesystem for atomic publication.
IMAGE_DIR="$(mktemp -d "$OUTPUT_DIR/.pastex-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/PasteX"
mkdir -p "$STAGING_DIR"

# ditto preserves the signed bundle and extended attributes. Do not add or edit
# anything inside the app after it has been signed and, when applicable, stapled.
ditto --rsrc --extattr "$APP_BUNDLE" "$STAGING_DIR/PasteX.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/安装说明.txt" <<'EOF'
PasteX 安装说明

1. 如果 PasteX 正在运行，请先从菜单栏退出。
2. 将此窗口中的 PasteX.app 拖入 Applications 文件夹。
   更新已有版本时，选择“替换”。
3. 复制完成后推出此磁盘映像，再从“应用程序”文件夹打开 PasteX。

请勿直接从磁盘映像运行 PasteX。
首次执行粘贴时，请根据应用提示允许辅助功能权限。
EOF

# This uses only macOS command-line tools and never launches Finder or requires
# a logged-in graphical session, so the same package works in GitHub Actions.
hdiutil create \
    -volname "PasteX" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$IMAGE_DIR/PasteX.dmg"
hdiutil verify "$IMAGE_DIR/PasteX.dmg"
# A hard link publishes the verified image atomically without overwriting a
# destination that may have appeared while hdiutil was running. Cleanup removes
# the temporary name, leaving only the requested output.
ln "$IMAGE_DIR/PasteX.dmg" "$DMG_PATH"

echo "Disk image: $DMG_PATH"
