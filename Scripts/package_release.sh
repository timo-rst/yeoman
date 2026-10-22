#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "============================================================"
echo "💂 Packaging Yeoman for Release"
echo "============================================================"

# 1. Run Automated Test Suite
echo ""
echo "==> Step 1: Running automated test suite..."
swift run YeomanTests

# 2. Build Release .app Bundle
echo ""
echo "==> Step 2: Building release application bundle..."
./Scripts/build_app.sh

APP_BUNDLE="dist/Yeoman.app"
ZIP_FILE="dist/Yeoman.zip"
DMG_FILE="dist/Yeoman.dmg"
DMG_STAGING="dist/dmg_staging"

# 3. Create Distribution ZIP (for Auto-Updater & Portable Archive)
echo ""
echo "==> Step 3: Creating release ZIP archive..."
rm -f "$ZIP_FILE"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"
echo "    Created: $ZIP_FILE ($(du -h "$ZIP_FILE" | cut -f1))"

# 4. Create Distribution DMG (with Drag-and-Drop /Applications symlink)
echo ""
echo "==> Step 4: Creating release DMG disk image..."
rm -rf "$DMG_STAGING" "$DMG_FILE"
mkdir -p "$DMG_STAGING"

# Copy App and create Applications link
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Set volume icon if icns is present
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns"
fi

# Build DMG using native macOS hdiutil
hdiutil create -volname "Yeoman" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_FILE"

rm -rf "$DMG_STAGING"
echo "    Created: $DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"

# 5. Output SHA256 Checksums
echo ""
echo "==> Step 5: Release artifacts & SHA256 checksums:"
echo "------------------------------------------------------------"
shasum -a 256 "$ZIP_FILE" "$DMG_FILE"
echo "------------------------------------------------------------"
echo ""
echo "🎉 Release packaging complete! Artifacts are ready in dist/"
