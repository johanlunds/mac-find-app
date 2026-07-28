#!/bin/zsh
# Renders the app icon and builds build/AppIcon.icns from Icon/make-icon.swift.
# build-app.sh calls this automatically when the icon is out of date.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swift Icon/make-icon.swift build/icon_1024.png

rm -rf build/AppIcon.iconset && mkdir build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
rm -rf build/AppIcon.iconset
echo "Built build/AppIcon.icns"
