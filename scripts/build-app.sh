#!/bin/bash
# Release pipeline: archive with Xcode, sign with the team's Developer ID certificate (managed by
# Xcode), notarize with Apple, staple the ticket, verify, and zip.
#
# Needs Xcode 16 or later with the Apple Developer account for team JLNFD3HP3G signed in under
# Xcode > Settings > Accounts. Xcode creates and stores the Developer ID certificate itself.
#
#   ./scripts/build-app.sh            # release: archive + Developer ID + notarize + staple + zip
#   ./scripts/build-app.sh dev        # local build signed with Apple Development, not notarized
#   ./scripts/build-app.sh ci         # unsigned compile check (no Apple account needed)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

MODE=${1:-release}
VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP_NAME="CR Subtitle Reader"
PROJECT=CRSubtitleReader.xcodeproj
SCHEME=CRSubtitleReader
ARCHIVE=build/CRSubtitleReader.xcarchive
DERIVED=build/DerivedData
mkdir -p build

# The project lists source files explicitly, so regenerate it whenever XcodeGen is available
# (cheap, and it picks up files added since the last generation).
if command -v xcodegen >/dev/null 2>&1; then
	echo "==> Regenerating $PROJECT from project.yml"
	xcodegen generate --quiet
fi

case "$MODE" in
ci)
	echo "==> Compile check (unsigned)"
	xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" \
		CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= build | grep -E "error:|BUILD"
	exit 0 ;;
dev)
	echo "==> Local build ($APP_NAME $VERSION, Apple Development signature, not notarized)"
	rm -rf "build/$APP_NAME.app"
	xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD"
	cp -R "$DERIVED/Build/Products/Release/$APP_NAME.app" build/
	echo "==> Done: build/$APP_NAME.app"
	exit 0 ;;
release) ;;
*)
	echo "usage: $0 [release|dev|ci]" >&2
	exit 2 ;;
esac

echo "==> Archiving $APP_NAME $VERSION (universal)"
rm -rf "$ARCHIVE" build/export build/notarized "build/$APP_NAME.app" build/notarize.log
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=macOS" \
	-archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" archive -allowProvisioningUpdates | grep -E "error:|ARCHIVE"
lipo -info "$ARCHIVE/Products/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "==> Signing with Developer ID and uploading to Apple's notary service"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
	-exportPath build/export -allowProvisioningUpdates | grep -E "error:|Uploaded|EXPORT"

echo "==> Waiting for Apple to notarize"
for attempt in $(seq 1 60); do
	if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath build/notarized >build/notarize.log 2>&1; then
		echo "notarized (attempt $attempt)"
		break
	fi
	if [ "$attempt" -eq 60 ]; then
		echo "notarization did not finish in 30 minutes; see build/notarize.log" >&2
		exit 1
	fi
	sleep 30
done
APP="build/notarized/$APP_NAME.app"
cp -R "$APP" "build/$APP_NAME.app"

echo "==> Verifying"
xcrun stapler validate "$APP" | tail -1
codesign --verify --deep --strict --verbose=1 "$APP"
spctl -a -vv -t exec "$APP" 2>&1 | grep -E "source=|origin="
if ! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.automation.apple-events"; then
	echo "refusing to package: the app lacks the apple-events entitlement (check project.yml / Resources/CRSubtitleReader.entitlements)" >&2
	exit 1
fi
echo "entitlement: apple-events OK"
if [ ! -f "$APP/Contents/Resources/CRSubtitleReaderBridge.scpt" ] && [ ! -f "$APP/Contents/Resources/CRSubtitleReaderBridge.applescript" ]; then
	echo "refusing to package: the AppleScript bridge is missing from the bundle" >&2
	exit 1
fi
[ -f "$APP/Contents/Resources/cr_subtitle_reader.user.js" ] || { echo "refusing to package: the userscript is missing from the bundle" >&2; exit 1; }
echo "bundle resources: bridge and userscript OK"

ZIP="build/CR-Subtitle-Reader-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "==> Done: build/$APP_NAME.app and $ZIP"
