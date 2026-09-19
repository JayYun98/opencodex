#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="$PWD/build/OpenCodex Monitor.app"
mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 6 -O -framework AppKit *.swift -o "$app/Contents/MacOS/OpenCodexMonitor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OpenCodexMonitor</string>
<key>CFBundleIdentifier</key><string>local.opencodex.monitor</string>
<key>CFBundleName</key><string>OpenCodex Monitor</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
"$app/Contents/MacOS/OpenCodexMonitor" --self-test
printf '%s\n' "$app"
