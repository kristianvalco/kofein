#!/bin/zsh
# Skompiluje Kofein.app do ./build a nainštaluje do /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Kofein.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1) ikona appky (vykreslí sa cez AppKit → .iconset → .icns)
#    štýl: amber | cream | dark | sunset   (napr. ICON_STYLE=dark ./build.sh)
ICON_STYLE="${ICON_STYLE:-cream}"
swiftc -O -o build/make-icon Tools/make-icon.swift
./build/make-icon build "$ICON_STYLE" >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# 2) samotná appka
swiftc -O -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/Kofein" Sources/main.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# 3) reinštalácia: ukonči bežiacu inštanciu a prekopíruj
pkill -x Kofein 2>/dev/null && sleep 1 || true
rm -rf /Applications/Kofein.app
cp -R "$APP" /Applications/Kofein.app
touch /Applications/Kofein.app   # nech si Finder všimne novú ikonu
open /Applications/Kofein.app

echo "Hotovo: /Applications/Kofein.app"
