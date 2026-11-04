#!/bin/bash
# Builds the downloadable Powered Notch and, optionally, publishes it as a GitHub release that
# the apps already installed pick up on their own.
#
#   scripts/release.sh                     -> dist/release/PoweredNotch.dmg + appcast.xml (nothing published)
#   scripts/release.sh 1.0.1               -> sets the version to 1.0.1 (commit), then builds
#   scripts/release.sh --publish [1.0.1]   -> also pushes and creates the GitHub release v<version>
#
# What gets published, as assets of the release:
#   PoweredNotch.dmg  the universal app (Apple Silicon + Intel). The website's button points to
#                     releases/latest/download/PoweredNotch.dmg, so the name never changes.
#   appcast.xml       the update feed. Installed apps read releases/latest/download/appcast.xml
#                     (SUFeedURL in project.yml) once a day; Sparkle downloads the new .dmg,
#                     checks its EdDSA signature against SUPublicEDKey and installs it.
#
# The version is MARKETING_VERSION in project.yml; the build number (CFBundleVersion, which
# Sparkle compares) is the number of commits, so it always grows.
#
# The update signature needs the Sparkle private key, kept in the login keychain under the
# account "powered-notch" (created with Sparkle's generate_keys). Without it no update can be
# published, so back it up:
#   .build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account powered-notch -x <file>
#
# Signing: ad hoc by default, because a downloadable app should not carry a personal
# "Apple Development" certificate. Set POWERED_NOTCH_SIGN_IDENTITY to a "Developer ID Application"
# identity to sign it properly, then notarize the .dmg with `xcrun notarytool submit … --wait` and
# `xcrun stapler staple`, so macOS opens it without the "Open Anyway" step.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PoweredNotch"
VOLUME_NAME="Powered Notch"
REPO="romeofrancesc0/powered-notch"
KEY_ACCOUNT="powered-notch"
OUT="dist/release"
DERIVED=".build/xcode-release"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"

PUBLISH=0
NEW_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    [0-9]*.[0-9]*.[0-9]*) NEW_VERSION="$arg" ;;
    *) echo "unknown option: $arg (use --publish and/or a version like 1.0.1)"; exit 1 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
current_version() { awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml; }

if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || { echo "The GitHub CLI is required to publish: brew install gh"; exit 1; }
  # A release is built from a commit, not from whatever happens to be in the folder.
  if [ -n "$(git status --porcelain)" ]; then
    echo "There are uncommitted changes: commit them (or stash them) before publishing."; exit 1
  fi
fi

if [ -n "$NEW_VERSION" ] && [ "$NEW_VERSION" != "$(current_version)" ]; then
  echo "▸ version $(current_version) → $NEW_VERSION"
  sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" project.yml
  git add project.yml
  git commit -q -m "Powered Notch $NEW_VERSION"
fi

VERSION="$(current_version)"
[ -n "$VERSION" ] || { echo "MARKETING_VERSION not found in project.yml"; exit 1; }
BUILD="$(git rev-list --count HEAD)"
TAG="v$VERSION"
echo "▸ Powered Notch $VERSION (build $BUILD)"

if [ "$PUBLISH" -eq 1 ] && gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists: choose a new version, e.g. scripts/release.sh --publish 1.0.1"; exit 1
fi

echo "▸ generating the Xcode project…"
xcodegen generate --quiet

echo "▸ building for Apple Silicon and Intel…"
LOG="$(mktemp -t powerednotch-release)"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
      -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION="$BUILD" -quiet build >"$LOG" 2>&1; then
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

# Sparkle.framework arrives with its signature broken (Xcode strips its headers when embedding it):
# sign its pieces again, inside out, in the order Sparkle's documentation gives.
sign_sparkle() {
  local fw="$1/Contents/Frameworks/Sparkle.framework"; shift
  [ -d "$fw" ] || return 0
  local v="$fw/Versions/B"
  for item in "$v/XPCServices/Installer.xpc" "$v/XPCServices/Downloader.xpc" "$v/Autoupdate" "$v/Updater.app"; do
    [ -e "$item" ] && codesign "$@" --preserve-metadata=entitlements "$item" >/dev/null 2>&1
  done
  codesign "$@" "$fw" >/dev/null 2>&1
}

IDENTITY="${POWERED_NOTCH_SIGN_IDENTITY:--}"
MEDIA_LIB="$(find "$APP/Contents" -name 'libPoweredNotchMediaBridge.dylib' | head -1)"
SIGN_FLAGS=(--force --timestamp=none --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then SIGN_FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY"); fi
[ -n "$MEDIA_LIB" ] && codesign "${SIGN_FLAGS[@]}" "$MEDIA_LIB"
sign_sparkle "$APP" "${SIGN_FLAGS[@]}"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
[ "$IDENTITY" = "-" ] && echo "▸ signed ad hoc" || echo "▸ signed with: $IDENTITY"

echo "▸ building the disk image…"
ln -s /Applications "$OUT/stage/Applications"
DMG="$OUT/$APP_NAME.dmg"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$OUT/stage"

echo "▸ signing the update…"
# prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" "$DMG")" || {
  echo "Could not sign the update: is the Sparkle key (account \"$KEY_ACCOUNT\") in the login keychain?"; exit 1
}

# Release notes: the commits since the previous release, or a first-release line.
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
NOTES="$OUT/notes.md"
: > "$NOTES"
if [ -n "$PREVIOUS" ]; then
  git log --no-merges --format='- %s' "$PREVIOUS"..HEAD | grep -v "^- Powered Notch [0-9]" > "$NOTES" || true
fi
[ -s "$NOTES" ] || echo "- First release." > "$NOTES"
NOTES_HTML="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|^- \(.*\)$|<li>\1</li>|' "$NOTES")"

cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Powered Notch</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Powered Notch $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$NOTES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$APP_NAME.dmg" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "▸ ready: $DMG ($SIZE) and $OUT/appcast.xml"

if [ "$PUBLISH" -eq 1 ]; then
  echo "▸ pushing $(git rev-parse --abbrev-ref HEAD)…"
  git push -q origin HEAD
  echo "▸ creating release $TAG"
  gh release create "$TAG" "$DMG" "$OUT/appcast.xml" -R "$REPO" \
    --target "$(git rev-parse HEAD)" --title "Powered Notch $VERSION" --notes-file "$NOTES" --latest
  echo "▸ published: https://github.com/$REPO/releases/tag/$TAG"
  echo "  installed copies will find it within a day (or at once with Check for Updates…)."
fi
