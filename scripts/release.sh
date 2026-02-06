#!/bin/bash

# Release Script for KnowledgeTool with Sparkle Auto-Update
# Usage: ./scripts/release.sh 1.2.0 "Bug fixes and improvements"
#
# This script:
# 1. Updates bundled binaries (yt-dlp, ffmpeg, ffprobe, node)
# 2. Updates version numbers in the project
# 3. Builds a self-contained release build
# 4. Verifies all dependencies are bundled
# 5. Creates a signed ZIP for distribution
# 6. Generates/updates the appcast.xml for Sparkle auto-update

set -e

VERSION="${1:-}"
RELEASE_NOTES="${2:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [release-notes]"
    echo "Example: $0 1.2.0 'Bug fixes and performance improvements'"
    exit 1
fi

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="Version $VERSION release"
fi

APP_NAME="KnowledgeTool"
BUNDLE_ID="com.knowledgetool.app"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
APPCAST_FILE="appcast.xml"
KEYS_DIR="$HOME/.sparkle-keys"

echo "=============================================="
echo " KnowledgeTool Release Builder v$VERSION"
echo "=============================================="
echo ""

# Check for signing key
if [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
    echo "Error: No Sparkle signing key found."
    echo "Run ./scripts/setup-sparkle.sh first to generate keys."
    exit 1
fi

# Step 1: Update bundled binaries
echo "[1/8] Updating bundled binaries..."
if [ -f "./scripts/update-binaries.sh" ]; then
    ./scripts/update-binaries.sh
else
    echo "     Skipping (update-binaries.sh not found)"
fi
echo ""

# Step 2: Update version in Xcode project
echo "[2/8] Updating version numbers..."
# Update version in project.pbxproj
PROJECT_FILE="KnowledgeTool.xcodeproj/project.pbxproj"
if [ -f "$PROJECT_FILE" ]; then
    # Update MARKETING_VERSION (display version)
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"
    # Update CURRENT_PROJECT_VERSION (build number - use date-based)
    BUILD_NUMBER=$(date +%Y%m%d%H%M)
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"
    echo "     Version: $VERSION"
    echo "     Build: $BUILD_NUMBER"
else
    echo "     Warning: project.pbxproj not found, skipping version update"
fi
echo ""

# Step 3: Clean and build
echo "[3/8] Building release..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Resolve dependencies first
echo "     Resolving Swift Package dependencies..."
xcodebuild -resolvePackageDependencies \
    -project KnowledgeTool.xcodeproj \
    -scheme KnowledgeTool \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    2>&1 | grep -E "^(Fetching|Resolving|Cloning|Checking)" || true

# Build with xcodebuild
echo "     Compiling release build..."
xcodebuild build \
    -project KnowledgeTool.xcodeproj \
    -scheme KnowledgeTool \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    -destination "platform=macOS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "(error:|warning:.*[^deprecated]|BUILD SUCCEEDED|BUILD FAILED)" || true

# Check build succeeded
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo ""
    echo "Error: Build failed. App not found at: $APP_PATH"
    echo "Run 'xcodebuild build -project KnowledgeTool.xcodeproj -scheme KnowledgeTool' for details."
    exit 1
fi

# Copy to build directory
cp -R "$APP_PATH" "$APP_DIR"
echo "     Build complete"
echo ""

# Step 4: Verify bundle contents
echo "[4/8] Verifying bundle contents..."
VERIFICATION_FAILED=0

# Check bundled binaries
BINARIES=("yt-dlp" "ffmpeg" "ffprobe" "node")
for bin in "${BINARIES[@]}"; do
    BIN_PATH="$APP_DIR/Contents/Resources/bin/$bin"
    if [ -f "$BIN_PATH" ]; then
        echo "     [OK] $bin bundled"
    else
        echo "     [FAIL] $bin NOT found in bundle"
        VERIFICATION_FAILED=1
    fi
done

# Check Sparkle framework
if [ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]; then
    echo "     [OK] Sparkle.framework bundled"
else
    echo "     [FAIL] Sparkle.framework NOT found"
    VERIFICATION_FAILED=1
fi

# Check main executable
if [ -f "$APP_DIR/Contents/MacOS/$APP_NAME" ]; then
    echo "     [OK] Main executable present"
else
    echo "     [FAIL] Main executable NOT found"
    VERIFICATION_FAILED=1
fi

# Check Info.plist
if [ -f "$APP_DIR/Contents/Info.plist" ]; then
    PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "     [OK] Info.plist present (version: $PLIST_VERSION)"
else
    echo "     [FAIL] Info.plist NOT found"
    VERIFICATION_FAILED=1
fi

if [ $VERIFICATION_FAILED -eq 1 ]; then
    echo ""
    echo "Error: Bundle verification failed. Check the build output."
    exit 1
fi
echo ""

# Step 5: Check for external dependencies
echo "[5/8] Checking for external dependencies..."
EXTERNAL_DEPS=$(otool -L "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null | grep -v "^build" | grep -v "/System/Library" | grep -v "/usr/lib" | grep -v "@rpath/Sparkle" || true)
if [ -n "$EXTERNAL_DEPS" ]; then
    echo "     Warning: Found external dependencies that may not be available on all systems:"
    echo "$EXTERNAL_DEPS" | sed 's/^/     /'
else
    echo "     [OK] All dependencies are system libraries or bundled"
fi
echo ""

# Step 6: Code sign the app
echo "[6/8] Code signing app bundle..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null
echo "     [OK] Ad-hoc signed"
echo ""

# Step 7: Create ZIP archive
echo "[7/8] Creating release archive..."
cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"
cd ..

ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
ZIP_SIZE_MB=$(echo "scale=2; $ZIP_SIZE / 1048576" | bc)
echo "     Archive: $ZIP_NAME ($ZIP_SIZE_MB MB)"
echo ""

# Step 8: Sign the update for Sparkle
echo "[8/8] Signing update with EdDSA..."
SPARKLE_SIGN="$HOME/.sparkle-tools/bin/Release/sign_update"
if [ -f "$SPARKLE_SIGN" ]; then
    SIGNATURE=$("$SPARKLE_SIGN" "$ZIP_PATH" -f "$KEYS_DIR/eddsa_private_key")
else
    # Manual signing with openssl
    SIGNATURE=$(openssl pkeyutl -sign -inkey "$KEYS_DIR/eddsa_private_key" \
        -rawin -in <(cat "$ZIP_PATH") 2>/dev/null | base64 | tr -d '\n')
fi
echo "     Signature: ${SIGNATURE:0:40}..."
echo ""

# Generate appcast.xml
GITHUB_USER="${GITHUB_USER:-geniesinc}"
GITHUB_REPO="${GITHUB_REPO:-knowledgetool}"
DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/v$VERSION/$ZIP_NAME"
APPCAST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/appcast.xml"
PUB_DATE=$(date -R)

cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>$APP_NAME Changelog</title>
        <link>$APPCAST_URL</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <description><![CDATA[
                <h2>What's New in $VERSION</h2>
                <p>$RELEASE_NOTES</p>
            ]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure
                url="$DOWNLOAD_URL"
                sparkle:version="$BUILD_NUMBER"
                sparkle:shortVersionString="$VERSION"
                sparkle:edSignature="$SIGNATURE"
                length="$ZIP_SIZE"
                type="application/octet-stream"/>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
        </item>
    </channel>
</rss>
EOF

echo "=============================================="
echo " Release v$VERSION Ready!"
echo "=============================================="
echo ""
echo "Files created:"
echo "  - $ZIP_PATH"
echo "  - $APPCAST_FILE"
echo ""
echo "Bundle contents:"
echo "  - Main app: $(du -sh "$APP_DIR" | cut -f1)"
echo "  - Binaries: yt-dlp, ffmpeg, ffprobe, node"
echo "  - Frameworks: Sparkle"
echo ""
echo "=============================================="
echo " Next Steps"
echo "=============================================="
echo ""
echo "1. Test the release locally:"
echo "   open $APP_DIR"
echo ""
echo "2. Commit appcast.xml:"
echo "   git add appcast.xml"
echo "   git commit -m 'Update appcast for v$VERSION'"
echo "   git push"
echo ""
echo "3. Create GitHub release:"
echo "   gh release create v$VERSION $ZIP_PATH \\"
echo "     --repo $GITHUB_USER/$GITHUB_REPO \\"
echo "     --title 'v$VERSION' \\"
echo "     --notes '$RELEASE_NOTES'"
echo ""
echo "4. Users install by:"
echo "   - Download $ZIP_NAME from GitHub releases"
echo "   - Unzip and drag to Applications"
echo "   - Run: xattr -cr /Applications/$APP_NAME.app"
echo "   - Open the app"
echo ""
