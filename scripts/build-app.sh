#!/usr/bin/env bash
# Builds a release Courier.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

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
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Courier.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Courier.app"
fi
