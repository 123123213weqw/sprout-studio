#!/bin/bash
# 打包 SproutPlayer.app + DMG(ad-hoc 签名)。
# 公证需要你自己的 Developer ID 证书与 Apple 账号:设置环境变量
#   SPROUT_SIGN_IDENTITY="Developer ID Application: ..." 
#   SPROUT_NOTARY_PROFILE=<notarytool profile 名>
# 后重跑本脚本即可切换为正式签名+公证。
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
APP="SproutPlayer.app"
STAGE=".app-stage"
DMG="SproutPlayer-$VERSION.dmg"

echo "== swift build -c release (SproutPlayer)"
(cd native && swift build -c release)

echo "== 组装 $APP"
rm -rf "$STAGE" "$APP"
mkdir -p "$STAGE/$APP/Contents/MacOS" "$STAGE/$APP/Contents/Resources"
cp native/.build/release/SproutPlayer "$STAGE/$APP/Contents/MacOS/SproutPlayer"
cp native/Sources/SproutPlayerResources/AppIcon.icns "$STAGE/$APP/Contents/Resources/AppIcon.icns"
cat > "$STAGE/$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sprout Player</string>
    <key>CFBundleDisplayName</key><string>Sprout Player</string>
    <key>CFBundleIdentifier</key><string>com.sproutstudio.player</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>SproutPlayer</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Sprout Player 不使用麦克风。</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Sprout 工程文件</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key><array><string>org.sproutstudio.sprout</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>org.sproutstudio.sprout</string>
            <key>UTTypeDescription</key><string>Sprout 工程文件</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>sprout</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "== 签名"
if [ -n "${SPROUT_SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --sign "$SPROUT_SIGN_IDENTITY" "$STAGE/$APP"
    if [ -n "${SPROUT_NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --wait --keychain-profile "$SPROUT_NOTARY_PROFILE" || true
        xcrun stapler staple "$STAGE/$APP" || true
    fi
else
    codesign --force --deep --sign - "$STAGE/$APP"
    echo "(ad-hoc 签名;分发给别人会触发 Gatekeeper 右键打开流程)"
fi

mv "$STAGE/$APP" .
rm -rf "$STAGE"

echo "== 生成 $DMG"
rm -f "$DMG"
hdiutil create -volname "Sprout Player" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "完成: $APP / $DMG"
