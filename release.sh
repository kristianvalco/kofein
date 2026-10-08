#!/bin/zsh
# Zbalí Kofein.app ako universal (Apple Silicon + Intel) do build/release/Kofein.zip
# Použitie: ./release.sh            → len zip
#           ./release.sh v1.0       → zip + GitHub release (cez `gh`)
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/release
APP=$OUT/Kofein.app
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ikona
ICON_STYLE="${ICON_STYLE:-cream}"
swiftc -O -o "$OUT/make-icon" Tools/make-icon.swift
"./$OUT/make-icon" "$OUT" "$ICON_STYLE" >/dev/null
iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# universal binárka
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "$OUT/Kofein-$arch" Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/Kofein" "$OUT/Kofein-arm64" "$OUT/Kofein-x86_64"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# zip (ditto zachová atribúty a podpis)
ditto -c -k --keepParent "$APP" "$OUT/Kofein.zip"
echo "Hotovo: $OUT/Kofein.zip"

if [[ -n "${1:-}" ]]; then
    gh release create "$1" "$OUT/Kofein.zip" --title "Kofein $1" --generate-notes
fi
