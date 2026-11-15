#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/Scripts/version.env"

ARCH="${1:?usage: package_dmg.sh <x86_64|arm64>}"
case "$ARCH" in
  x86_64)
    PLATFORM_SLUG="Intel-x86_64"
    VOL_NAME="Instagram AI Studio (Intel)"
    ;;
  arm64)
    PLATFORM_SLUG="AppleSilicon-arm64"
    VOL_NAME="Instagram AI Studio (Apple Silicon)"
    ;;
  *)
    echo "error: unsupported arch '$ARCH'" >&2
    exit 1
    ;;
esac

APP_SRC="$ROOT/build/apps/InstagramAIStudio-${VERSION}-macOS-${ARCH}.app"
OUT_DIR="$ROOT/build/release"
DMG_NAME="InstagramAIStudio-${VERSION}-macOS-${PLATFORM_SLUG}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
STAGE="$OUT_DIR/dmg-stage-${ARCH}"

if [[ ! -d "$APP_SRC" ]]; then
  echo "error: missing app bundle: $APP_SRC" >&2
  echo "Run: Scripts/package_macos_app.sh release $ARCH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"

cp -R "$APP_SRC" "$STAGE/${DISPLAY_NAME}.app"
ln -s /Applications "$STAGE/Applications"

# Optional background support folder (Finder may ignore without AppleScript styling).
mkdir -p "$STAGE/.background"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE"

echo "==> DMG created: $DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
file "$DMG_PATH"
