#!/bin/bash

# Package KnowledgeTool for distribution
# This creates a distributable zip with instructions

set -e

echo "📦 Packaging KnowledgeTool for distribution..."

# Build the app first
./build-app.sh

# Create distribution directory
DIST_DIR="KnowledgeTool-Distribution"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Copy the app
echo "📋 Copying app..."
cp -r build/KnowledgeTool.app "$DIST_DIR/"

# Create README for recipients
cat > "$DIST_DIR/README.txt" << 'EOF'
=================================
KnowledgeTool for macOS
=================================

INSTALLATION INSTRUCTIONS:

1. Unzip this folder
2. Open Terminal (in Applications/Utilities)
3. Run this command (drag KnowledgeTool.app into Terminal after typing the command):

   xattr -cr [drag app here]

   Example: xattr -cr /Users/yourname/Downloads/KnowledgeTool-Distribution/KnowledgeTool.app

4. Double-click KnowledgeTool.app to open

ALTERNATIVE METHOD:
- Right-click (or Control+click) on KnowledgeTool.app
- Select "Open" from the menu
- Click "Open" in the security dialog
- The app will now open normally going forward

REQUIREMENTS:
- macOS 15.0 (Sequoia) or later
- API Keys (configure in app Settings):
  * AssemblyAI (for transcription)
  * OpenAI (for summarization)

NOTE: All required binaries (yt-dlp, ffmpeg, ffprobe, Node.js) are bundled with this app.
No need to install Homebrew or any external dependencies!

WHAT THIS APP DOES:
- Transcribes interview videos with speaker identification
- Generates structured knowledge base summaries
- Extracts characteristic dialogue examples
- Designed specifically for interview content

For support or issues, please contact the person who shared this with you.

=================================
EOF

# Create a proper macOS zip
echo "🗜️  Creating distributable zip..."
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR" KnowledgeTool-Distribution.zip

# Cleanup
rm -rf "$DIST_DIR"

echo "✅ Distribution package created!"
echo "📍 Package location: KnowledgeTool-Distribution.zip"
echo ""
echo "📤 Send 'KnowledgeTool-Distribution.zip' to your friend"
echo "📖 It includes installation instructions in README.txt"
