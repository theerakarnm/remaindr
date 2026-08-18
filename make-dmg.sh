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

# 0. Signing preflight, before the build. A release run that cannot notarize
#    should fail in seconds, not after a full xcodebuild.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
NOTARIZED=0

if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  if [ -z "$IDENTITY" ]; then
    echo "ERROR: REQUIRE_NOTARIZATION=1 but no Developer ID Application identity is available." >&2
    echo "       Install one from developer.apple.com, or drop REQUIRE_NOTARIZATION for a local ad-hoc build." >&2
    exit 1
  fi
  if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "ERROR: REQUIRE_NOTARIZATION=1 but NOTARY_PROFILE is not set." >&2
    echo "       Store one once with:" >&2
    echo "         xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>" >&2
    exit 1
  fi
fi
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
rm -rf "$DIST" "$DMG" "$DMG.sha256"
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

# 5. Sign, notarize, staple, and then prove all three. Stapling is the last write
#    to the image; the checksum in step 6 is taken after it for exactly that reason.
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  # The image itself is signed, not just the app inside it: a ticket stapled to an
  # unsigned image cannot produce a Developer ID assessment.
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"

  SUBMIT_LOG="$LAYOUT_DIR/notary.txt"
  if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$SUBMIT_LOG"; then
    echo "ERROR: notarytool submit failed; see the output above." >&2
    exit 1
  fi
  # --wait has historically exited 0 on a rejected submission, so the verdict is
  # asserted from the output rather than inferred from the exit code.
  if ! grep -qE '^[[:space:]]*status: Accepted' "$SUBMIT_LOG"; then
    SUBMISSION_ID=$(awk '/^[[:space:]]*id:/ {print $2; exit}' "$SUBMIT_LOG")
    echo "ERROR: notarization was not Accepted; this DMG must not be published." >&2
    if [ -n "$SUBMISSION_ID" ]; then
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
  fi

  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  # Gatekeeper's own verdict on the artifact a user will actually double-click.
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
  NOTARIZED=1
else
  echo "WARNING: this DMG is NOT notarized (no Developer ID identity and/or no NOTARY_PROFILE)." >&2
  echo "         Gatekeeper will refuse it on any other Mac. Do not publish it." >&2
  echo "         Re-run with both set, and with REQUIRE_NOTARIZATION=1 to make this a hard failure." >&2
fi


# 6. Publish the SHA-256 sidecar. Taken AFTER stapling: `stapler staple` rewrites
#    the image, so a checksum computed before it would not match the download.
#    The sidecar is written on every path so the checksum machinery stays verifiable on
#    a machine with no signing identity, but ONLY a notarized run prints the instruction
#    to upload it: the README makes "ships a .sha256 sidecar" the marker of a release that
#    came from this pipeline, and an un-notarized build must never be invited to forge it.
DMG_NAME=$(basename "$DMG")
DMG_DIR=$(dirname "$DMG")
# The subshell cd keeps the bare filename in the sidecar, so a user can verify from
# whatever folder they downloaded both files into. The `&&` here is deliberate and is
# NOT the pattern Global Constraints warns about: a failing cd must abort the line,
# and under set -e the failing subshell aborts the script - which is what is wanted.
( cd "$DMG_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256" )
( cd "$DMG_DIR" && shasum -a 256 -c "$DMG_NAME.sha256" )

echo ""
echo "Created:   $DMG"
echo "Checksum:  $DMG.sha256"
cat "$DMG.sha256"
if [ "$NOTARIZED" = "1" ]; then
  echo "Notarized: yes, ticket stapled"
  echo ""
  echo "Upload BOTH $DMG_NAME and $DMG_NAME.sha256 to the GitHub release."
else
  echo "Notarized: NO - do not publish this build"
  echo ""
  echo "Do NOT upload this DMG or its sidecar. A published .sha256 is the marker of a"
  echo "notarized release; uploading one from this build would forge that signal."
fi
echo "Verify with: hdiutil verify $DMG"
