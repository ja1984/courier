#!/usr/bin/env bash
# Packs build/Courier.app into a drag-to-Applications disk image.
# Usage: scripts/make-dmg.sh <output.dmg>
# Signs the image when CODESIGN_IDENTITY is a Developer ID Application identity.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: make-dmg.sh <output.dmg>}"
APP="build/Courier.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/build-app.sh first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Courier.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT"
hdiutil create -volname "Courier" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null

if [[ "${CODESIGN_IDENTITY:-}" == Developer\ ID\ Application* ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$OUT"
  echo "Signed $OUT"
fi
echo "Built $OUT"
