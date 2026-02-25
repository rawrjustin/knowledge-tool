#!/bin/bash

# Update bundled binaries to their latest versions
# Run this before releasing to ensure all binaries are current
#
# IMPORTANT: ffmpeg and ffprobe MUST be statically linked builds.
# Never copy Homebrew binaries - they depend on dylibs in /opt/homebrew/
# that won't exist on other machines.

set -e

BIN_DIR="KnowledgeTool/Resources/bin"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "🔄 Updating bundled binaries..."
echo ""

# Update yt-dlp
echo "📥 Updating yt-dlp..."
YT_DLP_LATEST=$(curl -s https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
echo "   Latest version: $YT_DLP_LATEST"
curl -L -o "$BIN_DIR/yt-dlp" "https://github.com/yt-dlp/yt-dlp/releases/download/$YT_DLP_LATEST/yt-dlp_macos"
chmod +x "$BIN_DIR/yt-dlp"
echo "   ✅ yt-dlp updated to $YT_DLP_LATEST"
echo ""

# Update ffmpeg and ffprobe (static builds, universal arm64+x86_64)
echo "📥 Updating ffmpeg & ffprobe (static universal builds)..."
echo "   Downloading arm64 and x86_64 static builds from osxexperts.net..."

# Download arm64 builds
curl -L -o "$TEMP_DIR/ffmpeg-arm.zip" "https://www.osxexperts.net/ffmpeg80arm.zip"
curl -L -o "$TEMP_DIR/ffprobe-arm.zip" "https://www.osxexperts.net/ffprobe80arm.zip"

# Download x86_64 builds
curl -L -o "$TEMP_DIR/ffmpeg-intel.zip" "https://www.osxexperts.net/ffmpeg80intel.zip"
curl -L -o "$TEMP_DIR/ffprobe-intel.zip" "https://www.osxexperts.net/ffprobe80intel.zip"

# Extract
mkdir -p "$TEMP_DIR/arm" "$TEMP_DIR/intel"
unzip -o "$TEMP_DIR/ffmpeg-arm.zip" -d "$TEMP_DIR/arm/" > /dev/null
unzip -o "$TEMP_DIR/ffprobe-arm.zip" -d "$TEMP_DIR/arm/" > /dev/null
unzip -o "$TEMP_DIR/ffmpeg-intel.zip" -d "$TEMP_DIR/intel/" > /dev/null
unzip -o "$TEMP_DIR/ffprobe-intel.zip" -d "$TEMP_DIR/intel/" > /dev/null

# Create universal binaries
echo "   Creating universal binaries with lipo..."
lipo -create "$TEMP_DIR/arm/ffmpeg" "$TEMP_DIR/intel/ffmpeg" -output "$BIN_DIR/ffmpeg"
lipo -create "$TEMP_DIR/arm/ffprobe" "$TEMP_DIR/intel/ffprobe" -output "$BIN_DIR/ffprobe"
chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"

# Verify they're truly static (no Homebrew deps)
if otool -L "$BIN_DIR/ffmpeg" 2>/dev/null | grep -q "/opt/homebrew"; then
    echo "   ❌ ERROR: ffmpeg has Homebrew dependencies! Do NOT use Homebrew copies."
    exit 1
fi

echo "   ✅ ffmpeg & ffprobe updated (static universal arm64+x86_64)"
echo ""

# Note: Node.js is pinned to a specific LTS version for stability

echo "📋 Current binary versions:"
echo "   yt-dlp: $("$BIN_DIR/yt-dlp" --version 2>/dev/null || echo 'error')"
echo "   ffmpeg: $("$BIN_DIR/ffmpeg" -version 2>/dev/null | head -1 || echo 'error')"
echo "   ffprobe: $("$BIN_DIR/ffprobe" -version 2>/dev/null | head -1 || echo 'error')"
echo "   node: $("$BIN_DIR/node" --version 2>/dev/null || echo 'error')"
echo ""

# Verify all binaries are universal
echo "🔍 Verifying architectures:"
for bin in yt-dlp ffmpeg ffprobe; do
    ARCHS=$(file "$BIN_DIR/$bin" | grep -o "universal\|x86_64\|arm64" | sort -u | tr '\n' '+' | sed 's/+$//')
    echo "   $bin: $ARCHS"
done
echo ""

echo "✅ Binary update complete!"
