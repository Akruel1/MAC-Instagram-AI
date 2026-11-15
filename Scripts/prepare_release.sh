#!/bin/zsh
# Local Phase 3 release preparation. Does NOT commit, push, or publish.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/Scripts/version.env"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:${PATH:-}"

SIGN_MODE="${1:-none}"
HOST_ARCH="$(uname -m)"
OUT_DIR="$ROOT/build/release"
CHECKSUMS="$OUT_DIR/SHA256SUMS.txt"

echo "=============================================="
echo " Instagram AI Studio — Release Prep v${VERSION}"
echo " Host arch: ${HOST_ARCH}"
echo " Sign mode: ${SIGN_MODE}"
echo "=============================================="

"$ROOT/Scripts/generate_app_icon.sh"

echo "==> Swift tests"
cd "$ROOT"
swift test

echo "==> TestHarness"
swift run -c debug TestHarness

mkdir -p "$OUT_DIR"
rm -f "$CHECKSUMS"

for ARCH in x86_64 arm64; do
  echo "==> Package app ($ARCH)"
  "$ROOT/Scripts/package_macos_app.sh" release "$ARCH" "$SIGN_MODE"
  echo "==> Package DMG ($ARCH)"
  "$ROOT/Scripts/package_dmg.sh" "$ARCH"
done

{
  echo "# Instagram AI Studio ${VERSION} — SHA-256"
  echo "# Generated locally; not published until explicit approval."
  for f in "$OUT_DIR"/InstagramAIStudio-${VERSION}-macOS-*.dmg; do
    shasum -a 256 "$f"
  done
} | tee "$CHECKSUMS"

echo "==> Bundle validation summary"
for ARCH in x86_64 arm64; do
  APP="$ROOT/build/apps/InstagramAIStudio-${VERSION}-macOS-${ARCH}.app"
  BIN="$APP/Contents/MacOS/InstagramAIStudio"
  echo "--- $ARCH ---"
  /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist"
  file "$BIN"
  lipo -archs "$BIN"
  ls -la "$APP/Contents/Resources/AppIcon.icns"
  codesign -dv "$APP" 2>&1 | head -5 || echo "(unsigned)"
done

if [[ "$HOST_ARCH" == "x86_64" ]]; then
  echo "==> Intel runtime smoke: launching packaged Intel app briefly"
  INTEL_APP="$ROOT/build/apps/InstagramAIStudio-${VERSION}-macOS-x86_64.app"
  open "$INTEL_APP"
  sleep 2
  if pgrep -f "InstagramAIStudio-${VERSION}-macOS-x86_64.app/Contents/MacOS/InstagramAIStudio" >/dev/null; then
    echo "Intel smoke: process running"
  else
    # open may resolve to bundle name without version path; also check by CFBundleName process
    pgrep -lf InstagramAIStudio || echo "warning: process not detected"
  fi
fi

echo "==> Apple Silicon: compile/arch verified on this host; runtime requires arm64 Mac or CI."
echo "Artifacts in: $OUT_DIR"
ls -la "$OUT_DIR"
echo "DONE — no commit/push/release performed."
