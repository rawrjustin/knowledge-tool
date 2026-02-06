#!/bin/bash

# Update bundled binaries to their latest versions
# Run this before releasing to ensure all binaries are current

set -e

BIN_DIR="KnowledgeTool/Resources/bin"

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

# Note: ffmpeg and ffprobe are static builds that don't update frequently
# Node.js is pinned to a specific LTS version for stability

echo "📋 Current binary versions:"
echo "   yt-dlp: $("$BIN_DIR/yt-dlp" --version 2>/dev/null || echo 'error')"
echo "   ffmpeg: $("$BIN_DIR/ffmpeg" -version 2>/dev/null | head -1 || echo 'error')"
echo "   ffprobe: $("$BIN_DIR/ffprobe" -version 2>/dev/null | head -1 || echo 'error')"
echo "   node: $("$BIN_DIR/node" --version 2>/dev/null || echo 'error')"
echo ""
echo "✅ Binary update complete!"
echo ""
echo "Note: ffmpeg/ffprobe and node are updated less frequently."
echo "To update them manually, download from:"
echo "  - ffmpeg: https://evermeet.cx/ffmpeg/"
echo "  - node: https://nodejs.org/en/download/"
