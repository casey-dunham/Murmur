#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Murmur"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

# Parse args
RELEASE=false
RESIGN=false
if [[ "${1:-}" == "--release" ]]; then
    RELEASE=true
fi
if [[ "${1:-}" == "--resign" || "${2:-}" == "--resign" ]]; then
    RESIGN=true
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
    RESIGN=true  # Must sign on first creation
fi

# Update binary (in-place, preserves code signature as much as possible)
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Always update Info.plist and icon
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Only re-sign when explicitly requested or on first build
if $RESIGN; then
    echo "Signing with entitlements..."
    codesign --force --sign - \
        --entitlements "$PROJECT_DIR/Entitlements/$APP_NAME.entitlements" \
        "$APP_BUNDLE"
    echo ""
    echo "NOTE: You need to re-enable Accessibility permission for Murmur."
else
    echo "Skipping codesign (use --resign to force re-sign)"
fi

echo ""
echo "Build complete: $APP_BUNDLE"
echo "To run:  open $APP_BUNDLE"
