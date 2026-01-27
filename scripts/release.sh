#!/bin/bash

# Release Script for KnowledgeTool with Sparkle Auto-Update
# Usage: ./scripts/release.sh 1.2.0 "Bug fixes and improvements"

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

echo "🚀 Releasing $APP_NAME v$VERSION"
echo ""

# Check for signing key
if [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
    echo "❌ No signing key found. Run ./scripts/setup-sparkle.sh first"
    exit 1
fi

# Step 1: Update version in build script
echo "📝 Updating version numbers..."
sed -i '' "s/CFBundleShortVersionString<\/key>.*<string>[^<]*<\/string>/CFBundleShortVersionString<\/key>\n    <string>$VERSION<\/string>/" build-app.sh
# Also update build number (use date-based)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
sed -i '' "s/CFBundleVersion<\/key>.*<string>[^<]*<\/string>/CFBundleVersion<\/key>\n    <string>$BUILD_NUMBER<\/string>/" build-app.sh

# Step 2: Build the app
echo "🔨 Building app..."
./build-app.sh

# Step 3: Create ZIP archive
echo "📦 Creating release archive..."
cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"
cd ..

ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")

# Step 4: Sign the update
echo "✍️  Signing update with EdDSA..."

# Use Sparkle's sign_update if available, otherwise use openssl
SPARKLE_SIGN="$HOME/.sparkle-tools/bin/Release/sign_update"
if [ -f "$SPARKLE_SIGN" ]; then
    SIGNATURE=$("$SPARKLE_SIGN" "$ZIP_PATH" -f "$KEYS_DIR/eddsa_private_key")
else
    # Manual signing with openssl
    SIGNATURE=$(openssl pkeyutl -sign -inkey "$KEYS_DIR/eddsa_private_key" \
        -rawin -in <(cat "$ZIP_PATH") 2>/dev/null | base64 | tr -d '\n')
fi

echo "   Signature: ${SIGNATURE:0:20}..."

# Step 5: Generate/Update appcast.xml
echo "📋 Generating appcast.xml..."

# GitHub repo info
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

echo ""
echo "✅ Release prepared!"
echo ""
echo "📦 Release archive: $ZIP_PATH"
echo "📋 Appcast file: $APPCAST_FILE"
echo ""
echo "Next steps:"
echo ""
echo "1. Set your GitHub info (if not already):"
echo "   export GITHUB_USER=your-username"
echo "   export GITHUB_REPO=knowledge-tool"
echo ""
echo "2. Commit the appcast.xml to your main branch:"
echo "   git add appcast.xml"
echo "   git commit -m 'Update appcast for v$VERSION'"
echo "   git push"
echo ""
echo "3. Create a GitHub release:"
echo "   gh release create v$VERSION $ZIP_PATH --title 'v$VERSION' --notes '$RELEASE_NOTES'"
echo ""
echo "   Or manually:"
echo "   - Go to https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/new"
echo "   - Tag: v$VERSION"
echo "   - Upload: $ZIP_PATH"
echo ""
