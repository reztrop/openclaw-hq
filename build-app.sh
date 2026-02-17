#!/bin/bash
set -e

APP_NAME="OpenClaw HQ"
BUNDLE_NAME="OpenClaw HQ.app"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$BUNDLE_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building OpenClaw HQ..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/OpenClawDashboard" "$MACOS/OpenClawDashboard"

# Copy Info.plist
cp Info.plist "$CONTENTS/Info.plist"

# Generate app icon from Prism avatar if available
PRISM_AVATAR="$HOME/.openclaw/workspace/avatars/avatar_pictures/Prism_active.png"
if [ -f "$PRISM_AVATAR" ]; then
    echo "Generating app icon from Prism avatar..."
    ICONSET="$RESOURCES/AppIcon.iconset"
    mkdir -p "$ICONSET"

    sips -z 16 16     "$PRISM_AVATAR" --out "$ICONSET/icon_16x16.png"      > /dev/null 2>&1
    sips -z 32 32     "$PRISM_AVATAR" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null 2>&1
    sips -z 32 32     "$PRISM_AVATAR" --out "$ICONSET/icon_32x32.png"      > /dev/null 2>&1
    sips -z 64 64     "$PRISM_AVATAR" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null 2>&1
    sips -z 128 128   "$PRISM_AVATAR" --out "$ICONSET/icon_128x128.png"    > /dev/null 2>&1
    sips -z 256 256   "$PRISM_AVATAR" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$PRISM_AVATAR" --out "$ICONSET/icon_256x256.png"    > /dev/null 2>&1
    sips -z 512 512   "$PRISM_AVATAR" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$PRISM_AVATAR" --out "$ICONSET/icon_512x512.png"    > /dev/null 2>&1
    sips -z 1024 1024 "$PRISM_AVATAR" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1

    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
    rm -rf "$ICONSET"
    echo "App icon created from Prism avatar"
else
    echo "Warning: No Prism avatar found at $PRISM_AVATAR, app will use default icon"
fi

echo ""
echo "Done! App bundle created at:"
echo "  $APP_DIR"
echo ""
echo "To run:"
echo "  open \"$APP_DIR\""
echo ""
echo "To install to /Applications:"
echo "  cp -r \"$APP_DIR\" /Applications/"
