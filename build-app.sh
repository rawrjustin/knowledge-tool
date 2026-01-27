#!/bin/bash

# Build script for KnowledgeTool macOS app
# This script builds the app without requiring Xcode to be installed

set -e

echo "🔨 Building KnowledgeTool..."

# Configuration
APP_NAME="KnowledgeTool"
BUNDLE_ID="com.knowledgetool.app"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"

# Create app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create app icon (.icns)
echo "🎨 Creating app icon..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
ICON_SOURCE="KnowledgeTool/Resources/Assets.xcassets/AppIcon.appiconset"

# Copy icons directly without modification
cp "$ICON_SOURCE/Icon-iOS-Default-16x16@1x.png" "$ICONSET_DIR/icon_16x16.png"
cp "$ICON_SOURCE/Icon-iOS-Default-16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICON_SOURCE/Icon-iOS-Default-32x32@1x.png" "$ICONSET_DIR/icon_32x32.png"
cp "$ICON_SOURCE/Icon-iOS-Default-32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICON_SOURCE/Icon-iOS-Default-128x128@1x.png" "$ICONSET_DIR/icon_128x128.png"
cp "$ICON_SOURCE/Icon-iOS-Default-128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICON_SOURCE/Icon-iOS-Default-256x256@1x.png" "$ICONSET_DIR/icon_256x256.png"
cp "$ICON_SOURCE/Icon-iOS-Default-256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICON_SOURCE/Icon-iOS-Default-512x512@1x.png" "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_SOURCE/Icon-iOS-Default-512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# Copy bundled executables
echo "📦 Bundling yt-dlp, ffmpeg, ffprobe, and Node.js..."
mkdir -p "$RESOURCES_DIR/bin"
cp KnowledgeTool/Resources/bin/yt-dlp "$RESOURCES_DIR/bin/"
cp KnowledgeTool/Resources/bin/ffmpeg "$RESOURCES_DIR/bin/"
cp KnowledgeTool/Resources/bin/ffprobe "$RESOURCES_DIR/bin/"
cp KnowledgeTool/Resources/bin/node "$RESOURCES_DIR/bin/"
chmod +x "$RESOURCES_DIR/bin/yt-dlp"
chmod +x "$RESOURCES_DIR/bin/ffmpeg"
chmod +x "$RESOURCES_DIR/bin/ffprobe"
chmod +x "$RESOURCES_DIR/bin/node"

# Create temporary directory for processed files
TEMP_DIR="$BUILD_DIR/temp_sources"
mkdir -p "$TEMP_DIR"

echo "🔧 Preprocessing source files..."
# Copy and strip #Preview blocks from source files
# List of all Swift source files to compile
SOURCE_FILES=(
    KnowledgeTool/App/KnowledgeToolApp.swift
    KnowledgeTool/Views/DesignSystem.swift
    KnowledgeTool/Views/ContentView.swift
    KnowledgeTool/Views/SharedViews.swift
    KnowledgeTool/Views/OnboardingView.swift
    KnowledgeTool/Views/Video/VideoView.swift
    KnowledgeTool/Views/Article/ArticleView.swift
    KnowledgeTool/Views/TextSnippet/TextSnippetView.swift
    KnowledgeTool/Views/Settings/SettingsView.swift
    KnowledgeTool/Views/Characters/CharacterSelectorView.swift
    KnowledgeTool/Views/Characters/CharacterOverviewView.swift
    KnowledgeTool/Views/Characters/CharacterEditorView.swift
    KnowledgeTool/Views/Characters/CharacterCreationWizard.swift
    KnowledgeTool/Views/Characters/CharacterChatView.swift
    KnowledgeTool/Views/Characters/VersionHistoryView.swift
    KnowledgeTool/Views/Characters/VersionComparisonChatView.swift
    KnowledgeTool/Views/PromptTesting/PromptTestingView.swift
    KnowledgeTool/Views/PromptTesting/ChatVariantView.swift
    KnowledgeTool/Views/PromptTesting/SystemPromptEditorView.swift
    KnowledgeTool/Views/KnowledgeBase/KnowledgeBaseView.swift
    KnowledgeTool/ViewModels/VideoViewModel.swift
    KnowledgeTool/ViewModels/ArticleViewModel.swift
    KnowledgeTool/ViewModels/TextSnippetViewModel.swift
    KnowledgeTool/ViewModels/PromptTestingViewModel.swift
    KnowledgeTool/ViewModels/CharacterEditorViewModel.swift
    KnowledgeTool/ViewModels/CharacterCreationViewModel.swift
    KnowledgeTool/ViewModels/CharacterChatViewModel.swift
    KnowledgeTool/ViewModels/KnowledgeBaseViewModel.swift
    KnowledgeTool/ViewModels/SystemPromptEditorViewModel.swift
    KnowledgeTool/ViewModels/VersionComparisonViewModel.swift
    KnowledgeTool/Models/Models.swift
    KnowledgeTool/Models/Character.swift
    KnowledgeTool/Models/GitHubModels.swift
    KnowledgeTool/Models/PromptTest.swift
    KnowledgeTool/Services/VideoService.swift
    KnowledgeTool/Services/ArticleService.swift
    KnowledgeTool/Services/AssemblyAIService.swift
    KnowledgeTool/Services/OpenAIService.swift
    KnowledgeTool/Services/PerplexityService.swift
    KnowledgeTool/Services/PineconeService.swift
    KnowledgeTool/Services/MemoryGenerationService.swift
    KnowledgeTool/Services/CharacterRepository.swift
    KnowledgeTool/Services/LocalCharacterRepository.swift
    KnowledgeTool/Services/GitHubAuthService.swift
    KnowledgeTool/Services/GitHubAPIService.swift
    KnowledgeTool/Services/GitService.swift
    KnowledgeTool/Services/SparkleUpdater.swift
    KnowledgeTool/Utilities/APIKeyManager.swift
    KnowledgeTool/Utilities/DiffHighlighter.swift
    KnowledgeTool/Resources/ASP1Template.swift
)

for file in "${SOURCE_FILES[@]}"
do
    filename=$(basename "$file")
    # Remove #Preview blocks (they require Xcode macro system)
    # This handles both #Preview { and #Preview("name") { formats
    # Uses perl for better multiline regex handling
    perl -0777 -pe 's/^#Preview[^\{]*\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}//gms' "$file" > "$TEMP_DIR/$filename"
done

# Ensure all writes are complete before compilation
sync
sleep 1

# Compile Swift code
echo "⚙️  Compiling Swift code..."

# Build the list of temp source files from SOURCE_FILES array
TEMP_SOURCE_FILES=()
for file in "${SOURCE_FILES[@]}"; do
    filename=$(basename "$file")
    TEMP_SOURCE_FILES+=("$TEMP_DIR/$filename")
done

swiftc \
    -target arm64-apple-macosx15.0 \
    -swift-version 6 \
    -O \
    -enable-library-evolution \
    -strict-concurrency=complete \
    -framework SwiftUI \
    -framework Foundation \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -framework Security \
    "${TEMP_SOURCE_FILES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

# Clean up temp files
rm -rf "$TEMP_DIR"

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>knowledgetool</string>
            </array>
        </dict>
    </array>
    <!-- Sparkle Auto-Update Configuration -->
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/geniesinc/knowledgetool/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>Q/tcGhdXd80DgFpkugYcypCI9+cXeepMxo+wNc1d9YM=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

# Copy entitlements (for reference, not used in this build)
cp KnowledgeTool/Resources/KnowledgeTool.entitlements "$RESOURCES_DIR/"

# Set executable permissions
chmod +x "$MACOS_DIR/$APP_NAME"

# Ad-hoc sign the app (doesn't require Developer ID)
echo "✍️  Code signing app..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "⚠️  Code signing skipped (optional)"

echo "✅ Build complete!"
echo "📍 App location: $APP_DIR"
echo ""
echo "✨ This app includes all required binaries (yt-dlp, ffmpeg, ffprobe, Node.js)"
echo "   No external dependencies needed!"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To install to Applications:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "📦 To distribute to others:"
echo "  1. Zip the app: ditto -c -k --sequesterRsrc --keepParent $APP_DIR KnowledgeTool.zip"
echo "  2. Recipient must run: xattr -cr KnowledgeTool.app"
echo "  3. Then they can open it normally - no installations required!"
