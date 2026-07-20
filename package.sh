#!/bin/bash
# Package Eloquent as a distributable, nicely-styled .dmg
# (background image + drag-to-Applications layout).
#
# Basic usage (unsigned local build):
#   ./package.sh
#
# For distribution to OTHER Macs you must sign + notarize (see bottom).

set -euo pipefail

PROJECT="Eloquent.xcodeproj"
SCHEME="Eloquent"
APP_NAME="Eloquent"
VOL_NAME="Eloquent"
BUILD_DIR="build"
DMG_STAGE="$BUILD_DIR/dmg"
BG_SRC="dmg-assets/dmg-background.png"
DMG_TMP="$BUILD_DIR/${APP_NAME}-tmp.dmg"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"

# Window / icon layout (points).
# CONTENT_W/H are the visible content area = the background image size.
# The Finder window's outer bounds include the ~28pt title bar, so the outer
# height must be CONTENT_H + TITLEBAR for the background to line up exactly.
CONTENT_W=560
CONTENT_H=380
TITLEBAR=28
ICON_SIZE=112
APP_X=150; APP_Y=215        # icon positions in content coords (y from top of content)
APPS_X=410; APPS_Y=215

cd "$(dirname "$0")"

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_STAGE"

echo "==> Building Release"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  build | tail -2

APP_PATH=$(find "$BUILD_DIR/DerivedData/Build/Products/Release" -name "${APP_NAME}.app" -maxdepth 1 -type d | head -1)
[[ -z "$APP_PATH" ]] && { echo "ERROR: built app not found"; exit 1; }
echo "==> Built: $APP_PATH"

echo "==> Staging .dmg contents"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
# Hidden background folder
mkdir -p "$DMG_STAGE/.background"
cp "$BG_SRC" "$DMG_STAGE/.background/background.png"

echo "==> Creating writable .dmg"
rm -f "$DMG_TMP" "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$DMG_STAGE" \
  -fs HFS+ \
  -format UDRW \
  -ov "$DMG_TMP" >/dev/null

echo "==> Mounting to apply layout"
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
hdiutil attach "$DMG_TMP" -readwrite -noverify -noautoopen >/dev/null
sleep 2

echo "==> Applying Finder window styling"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $CONTENT_W, 120 + $CONTENT_H + $TITLEBAR}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to $ICON_SIZE
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
echo "==> Detaching"
hdiutil detach "$MOUNT_DIR" >/dev/null

echo "==> Converting to compressed final .dmg"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$DMG_TMP"

echo ""
echo "==> Done: $DMG_PATH"
echo ""
echo "NOTE: unsigned/un-notarized — runs on THIS Mac; other Macs show a Gatekeeper warning."
echo "To distribute widely, sign + notarize:"
echo "  codesign --deep --force --options runtime --sign \"Developer ID Application: NAME (TEAMID)\" \"$APP_PATH\""
echo "  xcrun notarytool submit \"$DMG_PATH\" --keychain-profile NOTARY --wait"
echo "  xcrun stapler staple \"$DMG_PATH\""
