#!/bin/bash
# Builds "CR Subtitle Reader.app" (universal) into build/ and zips it for release.
# Requires the Xcode Command Line Tools (swift, lipo, codesign, ditto, iconutil).
#   ./scripts/build-app.sh                       # release build, arm64 + x86_64
#   ARCHS=arm64 ./scripts/build-app.sh           # single architecture
#   CODESIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP_NAME="CR Subtitle Reader"
APP="build/$APP_NAME.app"
ARCHS=${ARCHS:-arm64 x86_64}
IDENTITY=${CODESIGN_IDENTITY:--}
mkdir -p build

echo "==> Building $APP_NAME $VERSION for: $ARCHS"
SLICES=()
for ARCH in $ARCHS; do
	TRIPLE="$ARCH-apple-macosx13.0"
	swift build -c release --triple "$TRIPLE" --product CRSubtitleReader
	SLICES+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/CRSubtitleReader")
done
if [ "${#SLICES[@]}" -gt 1 ]; then
	lipo -create "${SLICES[@]}" -output build/CRSubtitleReader-universal
	BIN="build/CRSubtitleReader-universal"
else
	BIN="${SLICES[0]}"
fi

if [ ! -f Resources/AppIcon.icns ]; then
	echo "==> Generating app icon"
	swiftc -O scripts/make-icon.swift -o build/make-icon
	build/make-icon Resources/AppIcon.icns
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp userscript/cr_subtitle_reader.user.js "$APP/Contents/Resources/"
cp applescript/CRSubtitleReaderBridge.applescript "$APP/Contents/Resources/"

echo "==> Signing ($IDENTITY)"
# The apple-events entitlement is mandatory under the Hardened Runtime; without it macOS silently
# refuses every Apple Event the app sends to Safari and VoiceOver (error -1743, no permission prompt).
codesign --force --deep --sign "$IDENTITY" --options runtime --entitlements Resources/CRSubtitleReader.entitlements "$APP"
codesign --verify --verbose=1 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.automation.apple-events" && echo "entitlement: apple-events OK"

ZIP="build/CR-Subtitle-Reader-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "==> Done: $APP and $ZIP"
