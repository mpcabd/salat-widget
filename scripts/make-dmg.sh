#!/bin/zsh
# Packages build/Salat.app into build/Salat-<version>.dmg (drag-to-Applications layout).
#   scripts/make-dmg.sh [version]
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="${1:-1.0.1}"
APP="build/Salat.app"
DMG="build/Salat-$VERSION.dmg"
STAGE="build/dmg-stage"

[[ -d "$APP" ]] || scripts/build-app.sh

/bin/rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
if command -v SetFile >/dev/null; then SetFile -a C "$STAGE"; fi

hdiutil create -volname "Salat" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
/bin/rm -rf "$STAGE"
shasum -a 256 "$DMG"
