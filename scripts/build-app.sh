#!/bin/bash
#
# 打包成可以直接双击的 深大电量.app
#
#   ./scripts/build-app.sh
#
# 产物在 dist/深大电量.app，把它拖进「应用程序」就能用。

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$DIST/深大电量.app"
VERSION="1.0.0"

echo "==> 编译 release"
swift build -c release

echo "==> 生成图标"
swift "$ROOT/scripts/make-icon.swift" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/SZUPower" "$APP/Contents/MacOS/SZUPower"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>深大电量</string>
    <key>CFBundleDisplayName</key><string>深大电量</string>
    <key>CFBundleIdentifier</key><string>com.szu.power</string>
    <key>CFBundleExecutable</key><string>SZUPower</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>需要连接校内网（192.168.84.3）向学校电控系统查询宿舍电表数据。</string>
</dict>
</plist>
PLIST

echo "==> 签名（ad-hoc）"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   签名失败，不影响本机使用"

echo ""
echo "完成：$APP"
echo "把它拖进「应用程序」文件夹即可。"
