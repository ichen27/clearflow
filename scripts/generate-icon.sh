#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets
icon_work="$(mktemp -d)"
trap 'rm -rf "$icon_work"' EXIT
mkdir "$icon_work/AppIcon.iconset"
swiftc scripts/render-app-icon.swift -o "$icon_work/render"
for size in 16 32 128 256 512; do
    "$icon_work/render" "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" "$size"
    "$icon_work/render" "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" "$((size * 2))"
done
cp "$icon_work/AppIcon.iconset/icon_512x512@2x.png" assets/AppIcon.png
iconutil -c icns "$icon_work/AppIcon.iconset" -o assets/AppIcon.icns
