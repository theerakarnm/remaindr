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
LAYOUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/remaindr-dmg.XXXXXX")
trap 'rm -rf "$LAYOUT_DIR"' EXIT
LAYOUT_SCRIPT="$LAYOUT_DIR/layout.applescript"

# 1. Build the app (must succeed with zero warnings - CI-style)
xcodebuild -project "$APP_NAME/$APP_NAME.xcodeproj" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" \
           build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG="build/$APP_NAME-$VERSION.dmg"

# 1b. Re-sign with the app's real entitlements.
#     Xcode's "Sign to Run Locally" fallback stamps the debug entitlement
#     com.apple.security.get-task-allow into Release builds, which leaves the
#     shipped binary attachable by a debugger. Re-signing with the explicit
#     entitlements file removes it. With a Developer ID identity present the
#     same re-sign produces a distributable signature.
ENTITLEMENTS="$APP_NAME/$APP_NAME/Remaindr.entitlements"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --options runtime --timestamp \
           --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
else
  echo "WARNING: no Developer ID identity found; re-signing ad-hoc (not notarized)." >&2
  codesign --force --sign - --options runtime \
           --entitlements "$ENTITLEMENTS" "$APP_PATH"
fi

# 1c. Refuse to ship any build that still carries the debug entitlement.
if codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
  echo "ERROR: $APP_PATH still carries com.apple.security.get-task-allow; not shipping." >&2
  exit 1
fi

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
  cat > "$LAYOUT_SCRIPT" <<'EOS'
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

# 4b. Apply the saved Finder layout to the final DMG. This must precede
#     notarization: stapling has to be the last write to the image.
if [ -f "$LAYOUT_SCRIPT" ]; then
  osascript "$LAYOUT_SCRIPT"
fi

# 5. Notarize and staple when both a Developer ID identity and a stored notary
#    profile exist. Store the profile once with:
#      xcrun notarytool store-credentials NOTARY_PROFILE --apple-id <id> --team-id <team>
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo ""
echo "Created: $DMG"
echo "Verify with: hdiutil verify $DMG"
