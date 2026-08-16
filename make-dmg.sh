#!/bin/bash
# make-dmg.sh - Build Remaindr (Release) and package it into a distributable .dmg
#
# Usage:  ./make-dmg.sh
# Output: build/Remaindr-<version>.dmg
#
# Optional polish: drop a 600x400 background image at dmg-resources/background.png
# and it will be used as the Finder window backdrop with a "drag to Applications"
# layout. Without it, the DMG is still created with a plain drag-to-install layout.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Remaindr"
SCHEME="Remaindr"
CONFIG="Release"
DERIVED="build/DerivedData"
DIST="build/dmg-staging"

# 1. Build the app (must succeed with zero warnings - CI-style)
xcodebuild -project "$APP_NAME/$APP_NAME.xcodeproj" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" \
           build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)
DMG="build/$APP_NAME-$VERSION.dmg"

# 2. Stage a clean folder: the .app + an /Applications shortcut
rm -rf "$DIST" "$DMG"
mkdir -p "$DIST"
cp -R "$APP_PATH" "$DIST/"
ln -s /Applications "$DIST/Applications"

# 3. Optional: background image + Finder layout (only when the resource exists)
BG="dmg-resources/background.png"
if [ -f "$BG" ]; then
  mkdir -p "$DIST/.background"
  cp "$BG" "$DIST/.background/background.png"
  cat > /tmp/dmg-applescript.txt <<'EOS'
on run
  tell application "Finder"
    tell disk "Remaindr"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {400, 160, 1000, 560}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 120
      set background picture of viewOptions to file ".background:background.png"
      set position of item "Remaindr.app" of container window to {150, 200}
      set position of item "Applications" of container window to {450, 200}
      update without registering applications
      close
    end tell
  end tell
end run
EOS
fi

# 4. Create the DMG (UDZO = zlib-compressed, the standard distributable format)
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$DIST" \
               -ov \
               -format UDZO \
               "$DMG"

# 5. Apply the saved Finder layout to the final DMG
if [ -f /tmp/dmg-applescript.txt ]; then
  osascript /tmp/dmg-applescript.txt
  rm -f /tmp/dmg-applescript.txt
fi

echo ""
echo "Created: $DMG"
echo "Verify with: hdiutil verify $DMG"
