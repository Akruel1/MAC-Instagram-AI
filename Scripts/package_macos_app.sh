#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/Scripts/version.env"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:${PATH:-}"

CONFIGURATION="${1:-release}"
ARCH="${2:-$(uname -m)}"   # x86_64 | arm64
SIGN_MODE="${3:-none}"     # none | adhoc | identity

case "$ARCH" in
  x86_64|arm64) ;;
  *)
    echo "error: unsupported arch '$ARCH' (expected x86_64 or arm64)" >&2
    exit 1
    ;;
esac

PRODUCT_DIR="$ROOT/.build/${CONFIGURATION}-${ARCH}"
BIN="$PRODUCT_DIR/InstagramAIStudio"
STAGE_ROOT="$ROOT/build/apps"
APP_DIR="$STAGE_ROOT/InstagramAIStudio-${VERSION}-macOS-${ARCH}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICNS="$ROOT/Resources/AppIcon/AppIcon.icns"

echo "==> Generating app icon (if needed)"
if [[ ! -f "$ICNS" ]]; then
  "$ROOT/Scripts/generate_app_icon.sh"
fi
if [[ ! -f "$ICNS" ]]; then
  echo "error: AppIcon.icns missing. Provide Resources/AppIcon/AppIcon-master.png and run Scripts/generate_app_icon.sh" >&2
  exit 1
fi

echo "==> Building $PRODUCT_NAME ($CONFIGURATION / $ARCH)"
cd "$ROOT"
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"

# Build for a specific architecture into an isolated directory.
swift build \
  -c "$CONFIGURATION" \
  --product InstagramAIStudio \
  --arch "$ARCH" \
  --scratch-path "$PRODUCT_DIR"

# SPM may place the binary under arch-specific subfolders depending on toolchain.
if [[ ! -x "$BIN" ]]; then
  FOUND="$(find "$PRODUCT_DIR" -type f -name InstagramAIStudio -perm +111 | head -n 1 || true)"
  if [[ -z "$FOUND" ]]; then
    echo "error: built binary not found under $PRODUCT_DIR" >&2
    exit 1
  fi
  BIN="$FOUND"
fi

echo "==> Verifying Mach-O architecture"
file "$BIN"
lipo -info "$BIN" || true
ACTUAL_ARCH="$(lipo -archs "$BIN" 2>/dev/null || true)"
if [[ "$ACTUAL_ARCH" != *"$ARCH"* ]]; then
  echo "error: binary arch '$ACTUAL_ARCH' does not include requested '$ARCH'" >&2
  exit 1
fi

echo "==> Assembling .app bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES"
cp "$BIN" "$MACOS_DIR/InstagramAIStudio"
chmod +x "$MACOS_DIR/InstagramAIStudio"
cp "$ICNS" "$RESOURCES/AppIcon.icns"

ARCH_LABEL="Intel x86_64"
[[ "$ARCH" == "arm64" ]] && ARCH_LABEL="Apple Silicon arm64"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>InstagramAIStudio</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS}</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>${ARCH}</string>
  </array>
  <key>IASArchitectureLabel</key>
  <string>${ARCH_LABEL}</string>
</dict>
</plist>
PLIST

# PkgInfo for classic Finder recognition
printf 'APPL????' > "$CONTENTS/PkgInfo"

case "$SIGN_MODE" in
  none)
    echo "==> Leaving bundle unsigned (no Developer ID available / not requested)"
    ;;
  adhoc)
    echo "==> Ad-hoc signing (development distribution only — not notarized)"
    codesign --force --deep --sign - "$APP_DIR"
    codesign -dv --verbose=2 "$APP_DIR" || true
    ;;
  identity)
    if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
      echo "error: CODESIGN_IDENTITY required for identity signing" >&2
      exit 1
    fi
    echo "==> Signing with identity: $CODESIGN_IDENTITY"
    codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    ;;
  *)
    echo "error: unknown SIGN_MODE '$SIGN_MODE'" >&2
    exit 1
    ;;
esac

echo "Packaged: $APP_DIR"
echo "Version:  $VERSION ($BUILD_NUMBER)"
echo "Arch:     $ARCH ($ARCH_LABEL)"
