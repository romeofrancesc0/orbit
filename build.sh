#!/bin/bash
# Builds Powered Notch and assembles the .app bundle.
#
#   ./build.sh              -> dist/PoweredNotch.app
#   ./build.sh --install    -> installs into ~/Applications and relaunches the app
#   ./build.sh --run        -> builds and launches from dist/
#
# Requires Xcode and XcodeGen (brew install xcodegen). The Xcode project is
# generated from project.yml and is not checked in.
#
# Code signing: set POWERED_NOTCH_SIGN_IDENTITY to pick an identity. Otherwise the
# first "Apple Development" certificate in your keychain is used, falling back to
# ad-hoc signing. A stable identity lets macOS remember the permissions you grant
# (Calendar, Camera, Accessibility) between builds; ad-hoc signing does not.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PoweredNotch"
DIST="dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
DERIVED=".build/xcode"

INSTALL=0
RUN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1; RUN=1 ;;
    --run)     RUN=1 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }

echo "▸ generating the Xcode project…"
xcodegen generate --quiet

echo "▸ building…"
LOG="$(mktemp -t powerednotch-build)"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
      -derivedDataPath "$DERIVED" -destination "platform=macOS,arch=$(uname -m)" -quiet build >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | sed 's|^.*/Sources/|Sources/|' | sort -u | head -60
  exit 1
fi
grep -E "warning: .*(Sources/PoweredNotch)" "$LOG" | sed 's|^.*/Sources/|Sources/|' | sort -u | head -20 || true

# The copy in the build folder must not answer to powerednotch:// links.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$DERIVED/Build/Products/Release/$APP_NAME.app" >/dev/null 2>&1 || true

echo "▸ assembling the bundle…"
rm -rf "${APP:?}"
mkdir -p "$DIST"
cp -R "$DERIVED/Build/Products/Release/$APP_NAME.app" "$APP"

IDENTITY="${POWERED_NOTCH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
IDENTITY="${IDENTITY:--}"

MEDIA_LIB="$(find "$APP/Contents" -name 'libPoweredNotchMediaBridge.dylib' | head -1)"
[ -n "$MEDIA_LIB" ] && codesign --force --sign "$IDENTITY" "$MEDIA_LIB" >/dev/null 2>&1
codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || echo "  (signing failed, not fatal)"
if [ "$IDENTITY" = "-" ]; then
  echo "▸ signed ad hoc (macOS will ask for permissions again after each build)"
else
  echo "▸ signed with: $IDENTITY"
fi
echo "▸ ready: $APP"

if [ "$INSTALL" -eq 1 ]; then
  mkdir -p "$INSTALL_DIR"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  rm -rf "${INSTALL_DIR:?}/${APP_NAME:?}.app"
  cp -R "$APP" "$INSTALL_DIR/"
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  APP="$INSTALL_DIR/$APP_NAME.app"
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
  echo "▸ installed in $APP"
fi

if [ "$RUN" -eq 1 ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  open "$APP"
  echo "▸ launched"
fi
