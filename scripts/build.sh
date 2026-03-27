#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Murmur"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

# Parse args
RELEASE=false
if [[ "${1:-}" == "--release" ]]; then
    RELEASE=true
fi

cd "$PROJECT_DIR"

# Build
echo "Building $APP_NAME..."
if $RELEASE; then
    swift build -c release
    BINARY="$BUILD_DIR/release/$APP_NAME"
else
    swift build
    BINARY="$BUILD_DIR/debug/$APP_NAME"
fi

# Create .app bundle structure if it doesn't exist
if [ ! -d "$APP_BUNDLE/Contents/MacOS" ]; then
    echo "Creating $APP_NAME.app bundle..."
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
fi

# Update binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Update Info.plist and icon
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Sign with stable Apple Development identity (preserves Accessibility permission across rebuilds)
IDENTITY="Apple Development: Casey Dunham (72JRKG8739)"
codesign --force --sign "$IDENTITY" \
    --entitlements "$PROJECT_DIR/Entitlements/$APP_NAME.entitlements" \
    "$APP_BUNDLE" 2>/dev/null

echo ""
echo "Build complete: $APP_BUNDLE"
echo "To run:  open $APP_BUNDLE"
