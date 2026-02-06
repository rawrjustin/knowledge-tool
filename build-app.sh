#!/bin/bash

# Build script for KnowledgeTool macOS app
# Uses xcodebuild to compile with full SPM dependency support

set -e

echo "🔨 Building KnowledgeTool..."

# Configuration
APP_NAME="KnowledgeTool"
PROJECT="KnowledgeTool.xcodeproj"
SCHEME="KnowledgeTool"
CONFIGURATION="Release"
BUILD_DIR="build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: xcodebuild not found. Please install Xcode."
    exit 1
fi

# Check that Xcode (not just Command Line Tools) is selected
DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || true)
if [[ "$DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    echo "❌ Error: Command Line Tools is selected instead of Xcode."
    echo "   Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Resolve SPM dependencies
echo "📦 Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    2>&1 | grep -E "^(Fetching|Resolving|Cloning|Checking)" || true

# Build the app
echo "⚙️  Compiling with xcodebuild..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    -destination "platform=macOS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | while read line; do
        # Show progress indicators
        if [[ "$line" == *"Compiling"* ]]; then
            echo "   Compiling: $(echo "$line" | sed 's/.*Compiling //' | cut -d' ' -f1)"
        elif [[ "$line" == *"Linking"* ]]; then
            echo "   Linking..."
        elif [[ "$line" == *"error:"* ]]; then
            echo "❌ $line"
        elif [[ "$line" == *"warning:"* ]] && [[ "$line" != *"deprecated"* ]]; then
            echo "⚠️  $line"
        fi
    done

# Check if build succeeded
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Build failed. App not found at: $APP_PATH"
    echo ""
    echo "Try running xcodebuild directly for more details:"
    echo "  xcodebuild build -project $PROJECT -scheme $SCHEME -configuration $CONFIGURATION"
    exit 1
fi

# Copy to build directory for easier access
echo "📍 Copying app to build directory..."
cp -R "$APP_PATH" "$BUILD_DIR/$APP_NAME.app"

# Ad-hoc sign the app
echo "✍️  Code signing app..."
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app" 2>/dev/null || echo "⚠️  Code signing skipped (optional)"

echo ""
echo "✅ Build complete!"
echo "📍 App location: $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To run the app:"
echo "  open $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To install to Applications:"
echo "  cp -r $BUILD_DIR/$APP_NAME.app /Applications/"
echo ""
echo "📦 To distribute to others:"
echo "  1. Zip the app: ditto -c -k --sequesterRsrc --keepParent $BUILD_DIR/$APP_NAME.app KnowledgeTool.zip"
echo "  2. Recipient must run: xattr -cr KnowledgeTool.app"
echo "  3. Then they can open it normally"
