#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="${1:-$ROOT/Resources/AppIcon/AppIcon-master.png}"
OUT_DIR="$ROOT/Resources/AppIcon"
ICONSET="$OUT_DIR/AppIcon.iconset"
ICNS="$OUT_DIR/AppIcon.icns"

if [[ ! -f "$MASTER" ]]; then
  echo "error: master icon not found: $MASTER" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICNS"
sips -z 256 256 "$MASTER" --out "$OUT_DIR/app-icon-256.png" >/dev/null

echo "Generated: $ICNS"
file "$ICNS"
