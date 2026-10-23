#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

MODE="${1:-development}"
if [[ "$MODE" != "development" && "$MODE" != "release" ]]; then
    echo "Usage: $0 [development|release]" >&2
    exit 1
fi
VERSION="${YEOMAN_VERSION:-0.2.2}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid YEOMAN_VERSION" >&2
    exit 1
fi
BUILD_VERSION="${YEOMAN_BUILD_VERSION:-4}"
if [[ ! "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid YEOMAN_BUILD_VERSION" >&2
    exit 1
fi
echo "==> Building Yeoman..."
swift build -c release

if [[ "$MODE" == "release" ]]; then
    .build/release/YeomanReleaseSign --check-trust
fi
APP_NAME="Yeoman"
BUILD_BIN=".build/release/$APP_NAME"
APP_BUNDLE="dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR" "$CONTENTS_DIR/Helpers"

cp "$BUILD_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp .build/release/YeomanInstaller "$CONTENTS_DIR/Helpers/YeomanInstaller"

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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
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
    <string>Copyright © 2026 trst. All rights reserved.</string>
</dict>
</plist>
EOF

# Developer ID and notarization are intentionally optional. Update publisher
# authentication is provided by the pinned Ed25519 key and signed ZIP manifest.
echo "==> Signing helper and application for integrity..."
codesign --force --sign - --options runtime "$CONTENTS_DIR/Helpers/YeomanInstaller"
codesign --force --sign - --options runtime "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "==> Created $APP_BUNDLE ($MODE)"
