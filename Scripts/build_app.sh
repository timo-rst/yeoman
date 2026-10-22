#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Building Yeoman in release mode..."
swift build -c release

APP_NAME="Yeoman"
BUILD_BIN=".build/release/$APP_NAME"
APP_BUNDLE="dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>de.trst.Yeoman</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Timo Richstein. All rights reserved.</string>
</dict>
</plist>
EOF

echo "==> Signing macOS App Bundle with stable designated requirement..."
codesign -s - -f --deep -r='designated => identifier "de.trst.Yeoman"' "$APP_BUNDLE"

if [ -f "Resources/AppIcon.icns" ]; then
    echo "==> Registering native custom icon with Finder..."
    swift -e '
    import AppKit
    let app = "'"$APP_BUNDLE"'"
    let icon = "Resources/AppIcon.icns"
    if let img = NSImage(contentsOfFile: icon) {
        _ = NSWorkspace.shared.setIcon(img, forFile: app, options: [])
    }
    '
fi

echo "==> Successfully created and signed $APP_BUNDLE!"
echo "You can launch it with: open $APP_BUNDLE"
