#!/bin/sh
# Builds build/Swivel.app (Apple Silicon, macOS 14+).
# SIGN_IDENTITY=<codesigning identity> keeps macOS permissions across rebuilds;
# without it the app is signed ad hoc and permissions must be granted again after each build.
set -eu
cd "$(dirname "$0")"
APP=build/Swivel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/Swivel"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/StatusIcon.png Resources/StatusIcon@2x.png "$APP/Contents/Resources/"
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist build/partial.plist >/dev/null

codesign --force --options runtime --entitlements Resources/Swivel.entitlements \
    --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
