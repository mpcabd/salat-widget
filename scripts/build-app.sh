#!/bin/zsh
# Builds Salat.app from the Swift package (no Xcode project required).
#   scripts/build-app.sh            -> build/Salat.app
#   scripts/build-app.sh --install  -> also copies it to /Applications and launches it
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="Salat"
BUNDLE_ID="com.mpcabd.salat"
VERSION="${SALAT_VERSION:-1.0.1}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

# Command Line Tools ship SDKs whose SwiftUI macros need Xcode's plugins; pick a CLT SDK that works.
if [[ "$(xcode-select -p)" == *CommandLineTools* && -z "${SDKROOT:-}" ]]; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
  done
fi
SCRATCH="$ROOT/.build-release"

echo "==> Compiling (release)"
if swift build -c release --scratch-path "$SCRATCH" --product Salat --arch arm64 --arch x86_64 2>/dev/null; then
  BIN="$(swift build -c release --scratch-path "$SCRATCH" --product Salat --arch arm64 --arch x86_64 --show-bin-path)/Salat"
else
  echo "    (universal build unavailable, building for this Mac only)"
  swift build -c release --scratch-path "$SCRATCH" --product Salat
  BIN="$(swift build -c release --scratch-path "$SCRATCH" --product Salat --show-bin-path)/Salat"
fi

echo "==> Assembling $APP"
/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Audio"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Audio/* "$APP/Contents/Resources/Audio/"

echo "==> Icon"
ICONSET="$OUT/AppIcon.iconset"
/bin/rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/Icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/Icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/bin/rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ar</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocationUsageDescription</key><string>Salat uses your location to calculate accurate prayer times and the Qibla direction.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Salat uses your location to calculate accurate prayer times and the Qibla direction.</string>
  <key>NSHumanReadableCopyright</key><string>Prayer times computed on-device. Azan recordings from Wikimedia Commons (see About).</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/$APP_NAME.app"
  echo "==> Installing to $DEST"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  /bin/rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
fi
