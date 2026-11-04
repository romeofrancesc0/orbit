#!/bin/bash
# Builds the downloadable Powered Notch: a universal app (Apple Silicon + Intel) in a disk image.
#
#   scripts/release.sh             -> dist/release/PoweredNotch.dmg
#   scripts/release.sh --publish   -> also creates the GitHub release v<version> with the .dmg attached
#
# The website's download button points to
#   https://github.com/romeofrancesc0/powered-notch/releases/latest/download/PoweredNotch.dmg
# so the file name must never change: every new release replaces it and the site needs no update.
#
# The version is MARKETING_VERSION in project.yml. Raise it before publishing a new release.
#
# Signing: ad hoc by default, because a downloadable app should not carry a personal
# "Apple Development" certificate. Set POWERED_NOTCH_SIGN_IDENTITY to a "Developer ID Application"
# identity to sign it properly, then notarize the .dmg with `xcrun notarytool submit … --wait` and
# `xcrun stapler staple`, so macOS opens it without the "Open Anyway" step.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PoweredNotch"
VOLUME_NAME="Powered Notch"
OUT="dist/release"
DERIVED=".build/xcode-release"
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] || { echo "MARKETING_VERSION not found in project.yml"; exit 1; }
echo "▸ Powered Notch $VERSION"

echo "▸ generating the Xcode project…"
xcodegen generate --quiet

echo "▸ building for Apple Silicon and Intel…"
LOG="$(mktemp -t powerednotch-release)"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
      -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | sed 's|^.*/Sources/|Sources/|' | sort -u | head -60
  echo "full log: $LOG"
  exit 1
fi

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
# The copy in the build folder must not answer to powerednotch:// links.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$BUILT" >/dev/null 2>&1 || true

rm -rf "$OUT"
mkdir -p "$OUT/stage"
cp -R "$BUILT" "$OUT/stage/"
APP="$OUT/stage/$APP_NAME.app"

echo "▸ checking architectures…"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

IDENTITY="${POWERED_NOTCH_SIGN_IDENTITY:--}"
MEDIA_LIB="$(find "$APP/Contents" -name 'libPoweredNotchMediaBridge.dylib' | head -1)"
SIGN_FLAGS=(--force --timestamp=none --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then SIGN_FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY"); fi
[ -n "$MEDIA_LIB" ] && codesign "${SIGN_FLAGS[@]}" "$MEDIA_LIB"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
[ "$IDENTITY" = "-" ] && echo "▸ signed ad hoc" || echo "▸ signed with: $IDENTITY"

echo "▸ building the disk image…"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -ov "$OUT/$APP_NAME.dmg"
rm -rf "$OUT/stage"
SIZE="$(du -h "$OUT/$APP_NAME.dmg" | cut -f1 | tr -d ' ')"
shasum -a 256 "$OUT/$APP_NAME.dmg" | tee "$OUT/$APP_NAME.dmg.sha256"
echo "▸ ready: $OUT/$APP_NAME.dmg ($SIZE)"

if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || { echo "The GitHub CLI is required to publish: brew install gh"; exit 1; }
  TAG="v$VERSION"
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "▸ release $TAG exists: replacing its disk image"
    gh release upload "$TAG" "$OUT/$APP_NAME.dmg" "$OUT/$APP_NAME.dmg.sha256" --clobber
  else
    echo "▸ creating release $TAG"
    gh release create "$TAG" "$OUT/$APP_NAME.dmg" "$OUT/$APP_NAME.dmg.sha256" \
      --title "Powered Notch $VERSION" --generate-notes --latest
  fi
  echo "▸ published: https://github.com/romeofrancesc0/powered-notch/releases/tag/$TAG"
fi
