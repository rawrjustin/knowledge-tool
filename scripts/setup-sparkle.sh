#!/bin/bash

# Sparkle Setup Script for KnowledgeTool
# Run this once to generate your EdDSA signing keys

set -e

echo "🔐 Setting up Sparkle auto-update signing..."

# Check if Sparkle is cloned
SPARKLE_DIR="$HOME/.sparkle-tools"
if [ ! -d "$SPARKLE_DIR" ]; then
    echo "📥 Downloading Sparkle tools..."
    git clone --depth 1 https://github.com/sparkle-project/Sparkle.git "$SPARKLE_DIR"
fi

# Build the signing tools if needed
GENERATE_KEYS="$SPARKLE_DIR/bin/generate_keys"
SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"

if [ ! -f "$GENERATE_KEYS" ]; then
    echo "🔨 Building Sparkle tools..."
    cd "$SPARKLE_DIR"
    xcodebuild -project Sparkle.xcodeproj -target generate_keys -configuration Release SYMROOT=bin 2>/dev/null || {
        echo "Using pre-built tools from Sparkle release instead..."
        # Download pre-built tools
        curl -L -o sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"
        tar -xf sparkle.tar.xz
        mkdir -p bin
        cp bin/generate_keys bin/sign_update bin/ 2>/dev/null || true
    }
fi

# Generate keys if they don't exist
KEYS_DIR="$HOME/.sparkle-keys"
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

if [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
    echo "🔑 Generating new EdDSA key pair..."

    # Use Sparkle's generate_keys if available, otherwise use openssl
    if [ -f "$SPARKLE_DIR/bin/Release/generate_keys" ]; then
        "$SPARKLE_DIR/bin/Release/generate_keys" -p "$KEYS_DIR"
    else
        # Manual key generation using openssl
        openssl genpkey -algorithm ED25519 -out "$KEYS_DIR/eddsa_private_key"
        openssl pkey -in "$KEYS_DIR/eddsa_private_key" -pubout -out "$KEYS_DIR/eddsa_public_key"

        # Extract just the base64 public key for the plist
        PUBLIC_KEY=$(openssl pkey -in "$KEYS_DIR/eddsa_private_key" -pubout -outform DER 2>/dev/null | tail -c 32 | base64)
        echo "$PUBLIC_KEY" > "$KEYS_DIR/eddsa_public_key_base64"
    fi

    echo "✅ Keys generated!"
    echo ""
    echo "⚠️  IMPORTANT: Your private key is stored at:"
    echo "   $KEYS_DIR/eddsa_private_key"
    echo ""
    echo "   Keep this PRIVATE and BACKED UP. You need it to sign every update."
    echo "   Never commit this to git!"
else
    echo "✅ Keys already exist at $KEYS_DIR"
fi

echo ""
echo "📋 Your PUBLIC key (add this to Info.plist):"
if [ -f "$KEYS_DIR/eddsa_public_key_base64" ]; then
    cat "$KEYS_DIR/eddsa_public_key_base64"
else
    echo "(Run generate_keys from Sparkle to get the public key in the right format)"
fi
echo ""
echo "Done! Next steps:"
echo "1. Add Sparkle package to Xcode (https://github.com/sparkle-project/Sparkle)"
echo "2. Add the public key to Info.plist as SUPublicEDKey"
echo "3. Add SUFeedURL pointing to your appcast.xml on GitHub"
