#!/bin/bash
# Compila Lunetta e ne assembla il bundle .app.
#
#   ./build.sh              → dist/Lunetta.app
#   ./build.sh --install    → installa in ~/Applications e riavvia l'app
#   ./build.sh --run        → costruisce e lancia da dist/
#
# Servono Xcode e XcodeGen (brew install xcodegen). Il progetto Xcode è generato
# da project.yml e non sta nel repository.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Lunetta"
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
    *) echo "opzione sconosciuta: $arg"; exit 1 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "serve XcodeGen: brew install xcodegen"; exit 1; }

echo "▸ genero il progetto…"
xcodegen generate --quiet

echo "▸ compilo…"
LOG="$(mktemp -t lunetta-build)"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
      -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' -quiet build >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | sed 's|^.*/Sources/|Sources/|' | sort -u | head -60
  exit 1
fi
grep -E "warning: .*(Sources/Lunetta)" "$LOG" | sed 's|^.*/Sources/|Sources/|' | sort -u | head -20 || true

# La copia nella cartella di build non deve rispondere ai link lunetta://.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$DERIVED/Build/Products/Release/$APP_NAME.app" >/dev/null 2>&1 || true

echo "▸ assemblo il bundle…"
rm -rf "${APP:?}"
mkdir -p "$DIST"
cp -R "$DERIVED/Build/Products/Release/$APP_NAME.app" "$APP"

# Un'identità stabile fa sì che macOS ricordi i permessi fra una build e l'altra:
# con la firma ad-hoc calendario, fotocamera e accessibilità andrebbero ridati ogni volta.
IDENTITY="${LUNETTA_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2}' | while read -r name; do
    if security find-certificate -c "$name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -q "OU=M67WJ8Q88G"; then
      echo "$name"; break
    fi
  done)"
fi
IDENTITY="${IDENTITY:--}"

MEDIA_LIB="$(find "$APP/Contents" -name 'libLunettaMediaBridge.dylib' | head -1)"
[ -n "$MEDIA_LIB" ] && codesign --force --sign "$IDENTITY" "$MEDIA_LIB" >/dev/null 2>&1
codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || echo "  (firma non riuscita, non è bloccante)"
echo "▸ firmato con: $IDENTITY"
echo "▸ pronto: $APP"

if [ "$INSTALL" -eq 1 ]; then
  mkdir -p "$INSTALL_DIR"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  rm -rf "${INSTALL_DIR:?}/${APP_NAME:?}.app"
  cp -R "$APP" "$INSTALL_DIR/"
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  APP="$INSTALL_DIR/$APP_NAME.app"
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
  echo "▸ installato in $APP"
fi

if [ "$RUN" -eq 1 ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  open "$APP"
  echo "▸ avviato"
fi
