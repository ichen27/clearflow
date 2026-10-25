#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Package the approved bitmap master without redrawing its artwork.
icon_work="$(mktemp -d)"
trap 'rm -rf "$icon_work"' EXIT
mkdir "$icon_work/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/AppIcon.png --out "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" assets/AppIcon.png --out "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work/AppIcon.iconset" -o assets/AppIcon.icns
