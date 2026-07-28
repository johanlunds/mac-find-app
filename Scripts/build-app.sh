#!/bin/zsh
# Builds "Find App.app" into ./build/ and installs the catalog.
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the icon in sync with its source script.
if [[ ! -f build/AppIcon.icns || Icon/make-icon.swift -nt build/AppIcon.icns ]]; then
  Scripts/make-icon.sh
fi

swift build -c release

APP="build/Find App.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/FindApp "$APP/Contents/MacOS/FindApp"
cp Resources/catalog.json "$APP/Contents/Resources/catalog.json"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleExecutable</key>
	<string>FindApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.johanlunds.FindApp</string>
	<key>CFBundleName</key>
	<string>Find App</string>
	<key>CFBundleDisplayName</key>
	<string>Find App</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

# Install catalog to Application Support so `swift run` builds find it too.
mkdir -p "$HOME/Library/Application Support/FindApp"
cp Resources/catalog.json "$HOME/Library/Application Support/FindApp/catalog.json"

echo "Built $APP"
echo "Install with: cp -R \"$APP\" /Applications/"
