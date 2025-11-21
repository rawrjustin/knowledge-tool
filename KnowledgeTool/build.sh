#!/bin/bash

# Knowledge Tool Build Script
# This script builds the Knowledge Tool macOS application

set -e

echo "🛠  Building Knowledge Tool..."
echo ""

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the KnowledgeTool directory."
    exit 1
fi

# Check if Swift is installed
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift is not installed or not in PATH."
    echo "Please install Xcode from the Mac App Store."
    exit 1
fi

# Check Swift version
echo "📋 Checking Swift version..."
swift --version

# Clean previous builds
echo ""
echo "🧹 Cleaning previous builds..."
swift package clean

# Build the project
echo ""
echo "🔨 Building Knowledge Tool (Release)..."
swift build -c release

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""
    echo "📦 The app is located at:"
    echo "   .build/release/KnowledgeTool"
    echo ""
    echo "To run the app:"
    echo "   .build/release/KnowledgeTool"
    echo ""
    echo "Or open in Xcode:"
    echo "   open Package.swift"
else
    echo ""
    echo "❌ Build failed. Please check the error messages above."
    exit 1
fi
