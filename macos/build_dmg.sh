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
# 临时 DMG 放到 mktemp 目录（避免 Spotlight/Finder 自动 reopen 当前工作目录里的 .dmg）
TMP_DIR=$(mktemp -d)
TMP_DMG="${TMP_DIR}/${APP_NAME}-tmp.dmg"
cleanup() { rm -rf "$STAGING" "$TMP_DIR" /tmp/gen_bg.swift /tmp/gen_bg; }
trap cleanup EXIT

# 确保临时 DMG 完全卸载（Finder/Spotlight 慢释放或 reopen 会导致 hdiutil convert 报 EAGAIN）
# 用 `mount | grep` 判断挂载点是否还在，比依赖 hdiutil info 的 image-path 更可靠：
# detach 成功后 image-path 仍可能短暂残留，但 mount 表里会立刻消失。
detach_tmp_dmg() {
    local mp="$1"
    [ -z "$mp" ] && return 0
    # 第一次尝试温和 detach，失败立即 force
    hdiutil detach "$mp" -quiet 2>/dev/null \
        || hdiutil detach "$mp" -force -quiet 2>/dev/null \
        || true
    # 兜底：循环 force detach，直到 mount 表里看不到这个挂载点（最多约 30s）
    local i
    for i in $(seq 1 20); do
        if ! mount 2>/dev/null | grep -Fq " on $mp "; then
            break
        fi
        hdiutil detach "$mp" -force -quiet 2>/dev/null || true
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

// 生成 DMG 安装窗口背景图。
// 视觉参考：Apifox 安装包风格 —— 粉紫到蓝绿的对角线柔和渐变，
// 顶部大标题 + 副标题，中间 5 个递进右箭头表示「拖入」动作，
// 底部一行操作指引。
//
// 不在背景图上绘制 "QuickBox" / "Applications" 文件名 ——
// Finder 会在图标下方自动渲染这两个文件名。

let args = CommandLine.arguments
guard args.count > 1 else { exit(1) }
let outputPath = args[1]

let w: CGFloat = 540
let h: CGFloat = 380
let size = NSSize(width: w, height: h)

let img = NSImage(size: size)
img.lockFocus()

// ── 1. 背景：粉紫 → 中间过渡 → 蓝绿，沿左上 → 右下对角线渐变 ──
let bg = NSGradient(colors: [
    NSColor(red: 0.93, green: 0.88, blue: 0.98, alpha: 1.00),  // 左上：粉紫
    NSColor(red: 0.93, green: 0.92, blue: 0.99, alpha: 1.00),  // 过渡：淡紫白
    NSColor(red: 0.82, green: 0.94, blue: 0.96, alpha: 1.00),  // 右下：浅蓝绿
])
// 315° 对应左上 → 右下方向
bg?.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 315)

// 在背景上叠一层 SF Symbols 风的浅点纹理，让背景不那么平
let dotColor = NSColor(white: 1, alpha: 0.55)
dotColor.setFill()
for row in stride(from: 18, through: h - 18, by: 36) {
    for col in stride(from: 18, through: w - 18, by: 36) {
        let r: CGFloat = 1.4
        let dot = NSBezierPath(ovalIn: NSRect(x: col - r, y: row - r, width: r * 2, height: r * 2))
        dot.fill()
    }
}

// 公共绘制工具：水平居中绘制文本
func drawCenteredText(_ text: String,
                      centerX: CGFloat,
                      baselineY: CGFloat,
                      fontSize: CGFloat,
                      weight: NSFont.Weight,
                      color: NSColor) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: centerX - sz.width / 2, y: baselineY))
}

// ── 2. 顶部大标题 "QuickBox" ──
drawCenteredText("QuickBox",
                 centerX: w / 2,
                 baselineY: h - 68,
                 fontSize: 30,
                 weight: .bold,
                 color: NSColor(red: 0.13, green: 0.13, blue: 0.18, alpha: 1))

// ── 3. 副标题 ──
drawCenteredText("极速搜索 · 一键启动 · 高效工作",
                 centerX: w / 2,
                 baselineY: h - 102,
                 fontSize: 13,
                 weight: .regular,
                 color: NSColor(white: 0.40, alpha: 1))

// ── 4. 中间 5 个右箭头 (V 形)，从浅到深 ──
// 图标在 Finder 中位于 (140, 210) 与 (400, 210)，背景图 y 反向，
// 对应背景图坐标 y = 380 - 210 = 170。
let arrowY: CGFloat = h - 210
let arrowStartX: CGFloat = 195
let arrowEndX: CGFloat = 345
let arrowCount = 5
let arrowSpacing = (arrowEndX - arrowStartX) / CGFloat(arrowCount - 1)
let arrowHalf: CGFloat = 6   // 箭头半宽
let arrowDepth: CGFloat = 7  // 箭头开口深度

for i in 0..<arrowCount {
    let cx = arrowStartX + CGFloat(i) * arrowSpacing
    // 透明度从左到右递增，做出「方向感」
    let alpha = 0.25 + 0.13 * CGFloat(i)
    let color = NSColor(red: 0.34, green: 0.46, blue: 0.78, alpha: alpha)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx - arrowDepth, y: arrowY + arrowHalf))
    path.line(to: NSPoint(x: cx, y: arrowY))
    path.line(to: NSPoint(x: cx - arrowDepth, y: arrowY - arrowHalf))
    path.lineWidth = 2.4
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

// ── 5. 底部操作指引 ──
drawCenteredText("将 QuickBox 拖入 Applications 文件夹完成安装",
                 centerX: w / 2,
                 baselineY: 30,
                 fontSize: 12,
                 weight: .regular,
                 color: NSColor(white: 0.45, alpha: 1))

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

# ---- 3–5. DMG：本地走「可写镜像 + Finder 布局 + 压缩」全流程；
#          CI 上挂载 Finder 在沙箱里不稳定，改为复用预制的 .DS_Store 模板，
#          再用 hdiutil create 一步打包（依然带背景图与图标布局）。----
DS_STORE_TEMPLATE="$(cd "$(dirname "$0")" && pwd)/dmg_assets/DS_Store.template"

if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${CI:-}" = "true" ]; then
    echo "==> Creating compressed DMG (CI：复用 .DS_Store 模板，跳过 Finder 挂载)..."
    if [ -f "$DS_STORE_TEMPLATE" ]; then
        cp "$DS_STORE_TEMPLATE" "$STAGING/.DS_Store"
        echo "    Applied DS_Store template"
    else
        echo "    (未找到 $DS_STORE_TEMPLATE，DMG 将使用 Finder 默认布局)"
    fi
    rm -f "$DMG_NAME"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -quiet -format UDZO -imagekey zlib-level=9 "$DMG_NAME"
else
    echo "==> Creating temporary DMG..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -format UDRW -fs HFS+ "$TMP_DMG"

    echo "==> Configuring DMG appearance..."
    # -nobrowse：降低 Finder 挂住卷的概率
    # 已知 volname = $APP_NAME，挂载点就是 /Volumes/$APP_NAME；
    # 不再依赖解析 hdiutil attach 输出（不同版本字段顺序/分隔符易变）。
    hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$TMP_DMG" -quiet
    MOUNT_POINT="/Volumes/$APP_NAME"

    # 等卷真正挂上（最多约 5s）
    for _i in 1 2 3 4 5; do
        if mount 2>/dev/null | grep -Fq " on $MOUNT_POINT "; then
            break
        fi
        sleep 1
    done

    if mount 2>/dev/null | grep -Fq " on $MOUNT_POINT "; then
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
                set text size of icon view options of container window to 12

                try
                    set background picture of icon view options of container window to file ".background:background.png"
                end try

                set position of item "${APP_NAME}.app" of container window to {140, 210}
                set position of item "Applications" of container window to {400, 210}

                -- 主动把窗口属性写入 .DS_Store，避免 close 之后 Finder 还在异步刷盘
                update without registering applications
                delay 2
                close
            end tell
        end tell
EOF

        # 等 Finder 异步完成 .DS_Store 写入；不够长 detach 会被 reopen
        sleep 3
        sync

        # 本地路径每次都同步一份最新的 .DS_Store 到仓库模板，
        # 这样后续 CI 构建可以复用相同的窗口/图标布局。
        if [ -f "$MOUNT_POINT/.DS_Store" ]; then
            mkdir -p "$(dirname "$DS_STORE_TEMPLATE")"
            cp "$MOUNT_POINT/.DS_Store" "$DS_STORE_TEMPLATE"
            echo "    Synced .DS_Store -> $DS_STORE_TEMPLATE"
        fi

        detach_tmp_dmg "$MOUNT_POINT"
    fi

    echo "==> Compressing final DMG..."
    hdiutil_convert_with_retry
    rm -f "$TMP_DMG"
fi

echo ""
echo "Done! DMG created: $DMG_NAME"
