#!/bin/bash
# build_dmg.sh — Create a polished macOS DMG installer for QuickBox
#
# Usage: ./build_dmg.sh <path-to-app-bundle> <version>
#
# Produces: QuickBox-<version>.dmg
# The DMG includes the app bundle, an Applications symlink, a custom
# background with drag-to-Applications instruction, and (when not on CI)
# proper icon positioning via Finder — the standard macOS installer experience.
# On GITHUB_ACTIONS/CI, a single UDZO create step is used to avoid hdiutil convert EAGAIN.

set -euo pipefail

APP_SRC="$1"
VERSION="$2"
APP_NAME="QuickBox"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
TMP_DMG="${APP_NAME}-tmp.dmg"

if [ ! -d "$APP_SRC" ]; then
    echo "Error: App bundle not found at '$APP_SRC'"
    exit 1
fi
if [ -z "$VERSION" ]; then
    echo "Error: Version not specified"
    exit 1
fi

echo "==> Creating DMG for $APP_NAME v$VERSION"
echo "    App source: $APP_SRC"

# ---- 1. Prepare staging directory ----
STAGING=$(mktemp -d)
cleanup() { rm -rf "$STAGING" /tmp/gen_bg.swift /tmp/gen_bg; }
trap cleanup EXIT

# 确保临时 DMG 完全卸载（CI 上 Finder/Spotlight 慢释放会导致 hdiutil convert 报 EAGAIN）
detach_tmp_dmg() {
    local mp="$1"
    [ -z "$mp" ] && return 0
    if ! hdiutil detach "$mp" -quiet 2>/dev/null; then
        sleep 1
        hdiutil detach "$mp" -force -quiet 2>/dev/null || true
    fi
    # 等待镜像不再处于 busy 状态（最多约 22s）
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if ! hdiutil info 2>/dev/null | grep -Fq "$TMP_DMG"; then
            break
        fi
        sleep 1.5
    done
    sync
}

hdiutil_convert_with_retry() {
    local attempt=1 max_attempts=12 base_sleep=3
    while [ "$attempt" -le "$max_attempts" ]; do
        rm -f "$DMG_NAME"
        sync
        # -quiet 减少日志噪声；-ov 与事先 rm 一致，双保险
        if hdiutil convert "$TMP_DMG" -quiet -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_NAME"; then
            return 0
        fi
        echo "    (convert 第 $attempt 次失败，${max_attempts} 次内重试，等待释放 DMG…)"
        # 指数退避：CI/Spotlight 释放较慢时比固定 3s 更有效
        sleep $((base_sleep + attempt * 2))
        attempt=$((attempt + 1))
    done
    return 1
}

echo "==> Copying app bundle..."
cp -R "$APP_SRC" "$STAGING/${APP_NAME}.app"

echo "==> Creating Applications symlink..."
ln -s /Applications "$STAGING/Applications"

# ---- 2. Generate custom background image ----
echo "==> Generating DMG background image..."
mkdir -p "$STAGING/.background"

SWIFT_SCRIPT="/tmp/gen_bg.swift"
SWIFT_BIN="/tmp/gen_bg"

cat > "$SWIFT_SCRIPT" << 'SWIFT'
import Cocoa

let args = CommandLine.arguments
guard args.count > 1 else { exit(1) }
let outputPath = args[1]

let w: CGFloat = 540
let h: CGFloat = 380
let size = NSSize(width: w, height: h)

let img = NSImage(size: size)
img.lockFocus()

// Gradient background
let g = NSGradient(
    starting: NSColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1),
    ending: NSColor(red: 0.978, green: 0.98, blue: 0.984, alpha: 1)
)
g?.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)

func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: text, attributes: attrs)
    let strSize = str.size()
    str.draw(at: NSPoint(x: x - strSize.width / 2, y: y))
}

func drawArrow(from x1: CGFloat, to x2: CGFloat, y: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = 2.5
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    path.move(to: NSPoint(x: x1, y: y))
    path.line(to: NSPoint(x: x2, y: y))

    let head: CGFloat = 8
    path.move(to: NSPoint(x: x2, y: y))
    path.line(to: NSPoint(x: x2 - head, y: y - head))
    path.move(to: NSPoint(x: x2, y: y))
    path.line(to: NSPoint(x: x2 - head, y: y + head))

    let dash: [CGFloat] = [5, 3]
    path.setLineDash(dash, count: 2, phase: 0)
    NSColor(white: 0.5, alpha: 1).setStroke()
    path.stroke()
}

// Arrow between icons
drawArrow(from: 180, to: 360, y: 210)

// Icon labels
drawText("QuickBox", x: 140, y: 140, size: 13, weight: .medium, color: NSColor(white: 0.35, alpha: 1))
drawText("Applications", x: 400, y: 140, size: 13, weight: .medium, color: NSColor(white: 0.35, alpha: 1))

// Bottom instruction
drawText("Drag QuickBox to your Applications folder",
         x: w / 2, y: 40, size: 14, weight: .regular, color: NSColor(white: 0.5, alpha: 1))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
    exit(1)
}
try? png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT

if swiftc -o "$SWIFT_BIN" "$SWIFT_SCRIPT" 2>/dev/null; then
    "$SWIFT_BIN" "$STAGING/.background/background.png" 2>/dev/null || true
    echo "    Background image created"
else
    echo "    (swiftc not available — creating DMG without background)"
fi

# ---- 3–5. DMG：本地做「可写镜像 + Finder 布局 + 压缩」；CI 上跳过挂载（避免 hdiutil convert EAGAIN）----
if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${CI:-}" = "true" ]; then
    echo "==> Creating compressed DMG (CI：跳过 Finder 定制挂载，避免 convert 资源争用)..."
    rm -f "$DMG_NAME"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -quiet -format UDZO -imagekey zlib-level=9 "$DMG_NAME"
else
    echo "==> Creating temporary DMG..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -format UDRW -fs HFS+ "$TMP_DMG"

    echo "==> Configuring DMG appearance..."
    # -nobrowse：降低 Finder 挂住卷的概率
    MOUNT_POINT=$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$TMP_DMG" 2>/dev/null | \
        grep "/Volumes/$APP_NAME" | awk '{$1=$2=$3=""; sub(/^[[:space:]]+/, ""); print}')

    if [ -n "$MOUNT_POINT" ]; then
        sleep 2

        osascript <<-EOF 2>/dev/null || true
        tell application "Finder"
            tell disk "$APP_NAME"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set bounds of container window to {200, 120, 740, 500}
                set arrangement of icon view options of container window to not arranged
                set icon size of icon view options of container window to 80

                try
                    set background picture of icon view options of container window to file ".background:background.png"
                end try

                set position of item "${APP_NAME}.app" of container window to {140, 210}
                set position of item "Applications" of container window to {400, 210}

                close
            end tell
        end tell
EOF

        sleep 2
        detach_tmp_dmg "$MOUNT_POINT"
    fi

    echo "==> Compressing final DMG..."
    hdiutil_convert_with_retry
    rm -f "$TMP_DMG"
fi

echo ""
echo "Done! DMG created: $DMG_NAME"
