#!/usr/bin/env bash
# Builds a release Courier.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftUI's macros (@State etc.) ship only with Xcode, not with the Command Line Tools.
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ "$DEV_DIR" != *.app/Contents/Developer ]]; then
  cat >&2 <<MSG
error: Courier needs Xcode to build, but the active developer directory is:
  ${DEV_DIR:-<none>}
The Command Line Tools don't include SwiftUI's macro plugin, so the build fails with
"plugin for module 'SwiftUIMacros' not found". Install Xcode, then either:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
or run once with:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $0
MSG
  exit 1
fi

# Regenerate the icon when the master PNG is newer than the .icns.
if [ ! -f Resources/AppIcon.icns ] || [ Resources/AppIcon.png -nt Resources/AppIcon.icns ]; then scripts/make-icon.sh; fi

swift build -c release --product Courier
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Courier.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Courier" "$APP/Contents/MacOS/Courier"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a stable identity when one exists, so the Keychain keeps recognising the app
# across rebuilds (ad-hoc signatures change every build). Override with CODESIGN_IDENTITY.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "Signed with: ${IDENTITY:-ad-hoc}"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Courier.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Courier.app"
fi
