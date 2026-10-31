#!/bin/bash
# Compila AgentBar e ne assembla il bundle .app.
#
#   ./build.sh              → dist/AgentBar.app
#   ./build.sh --install    → installa in ~/Applications e riavvia l'app
#   ./build.sh --run        → costruisce e lancia da dist/

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AgentBar"
BUNDLE_ID="com.francescoromeo.agentbar"
VERSION="1.0.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

INSTALL=0
RUN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1; RUN=1 ;;
    --run)     RUN=1 ;;
    *) echo "opzione sconosciuta: $arg"; exit 1 ;;
  esac
done

echo "▸ compilo ($APP_NAME $VERSION)…"
swift build -c release

echo "▸ assemblo il bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Solo barra di stato: niente Dock, niente menu applicazione. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Firma ad-hoc: identità stabile per login item e permessi di sistema.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (firma ad-hoc non riuscita, non è bloccante)"

echo "▸ pronto: $APP"

if [ "$INSTALL" -eq 1 ]; then
  mkdir -p "$INSTALL_DIR"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  APP="$INSTALL_DIR/$APP_NAME.app"
  echo "▸ installato in $APP"
fi

if [ "$RUN" -eq 1 ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  open "$APP"
  echo "▸ avviato"
fi
