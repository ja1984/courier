#!/usr/bin/env bash
# Builds Resources/AppIcon.icns from the 1024px master Resources/AppIcon.png.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="Resources/AppIcon.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET")"
echo "Wrote Resources/AppIcon.icns"
