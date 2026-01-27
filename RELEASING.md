# Releasing KnowledgeTool

This guide covers how to create and publish new releases with automatic updates via Sparkle.

## Quick Release (TL;DR)

```bash
# 1. Build, sign, and create release files
./scripts/release.sh 1.2.0 "Brief description of changes"

# 2. Commit and push the appcast
git add appcast.xml
git commit -m "Update appcast for v1.2.0"
git push geniesinc HEAD:main

# 3. Create the GitHub release
gh release create v1.2.0 build/KnowledgeTool-1.2.0.zip \
  --repo geniesinc/knowledgetool \
  --title "v1.2.0" \
  --notes "Release notes here"
```

---

## Detailed Steps

### 1. Run the Release Script

```bash
./scripts/release.sh <version> "<release notes>"
```

**Example:**
```bash
./scripts/release.sh 1.2.0 "Added dark mode support and fixed video transcription bugs"
```

This script:
- Updates version numbers in the build
- Builds the app via `build-app.sh`
- Creates a signed zip archive at `build/KnowledgeTool-<version>.zip`
- Signs the archive with your EdDSA key
- Generates/updates `appcast.xml` with the new release info

### 2. Commit the Appcast

The `appcast.xml` file tells Sparkle about available updates. Push it to main:

```bash
git add appcast.xml
git commit -m "Update appcast for v1.2.0"
git push geniesinc HEAD:main
```

### 3. Create the GitHub Release

```bash
gh release create v1.2.0 build/KnowledgeTool-1.2.0.zip \
  --repo geniesinc/knowledgetool \
  --title "v1.2.0" \
  --notes "Release notes here"
```

Or create it manually at: https://github.com/geniesinc/knowledgetool/releases/new

**Important:** The zip filename must match what's in `appcast.xml`:
- Tag: `v1.2.0`
- Asset: `KnowledgeTool-1.2.0.zip`

---

## How Auto-Updates Work

1. User's app checks `appcast.xml` periodically (hosted on GitHub raw)
2. Sparkle compares versions and shows update prompt if newer version exists
3. User clicks "Install Update"
4. Sparkle downloads the zip, verifies the EdDSA signature, and installs

**Appcast URL:** `https://raw.githubusercontent.com/geniesinc/knowledgetool/main/appcast.xml`

---

## Signing Keys

Your EdDSA signing keys are stored at `~/.sparkle-keys/`:

| File | Purpose |
|------|---------|
| `eddsa_private_key` | Original PEM format (openssl generated) |
| `eddsa_private_key_raw` | Base64 format for Sparkle's `sign_update` tool |
| `eddsa_public_key_base64` | Public key embedded in the app's Info.plist |

**⚠️ CRITICAL:** Back up `~/.sparkle-keys/` securely. If you lose these keys, users won't be able to verify updates and you'll need to release a new version with new keys.

---

## Version Numbering

Use semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR:** Breaking changes or major new features
- **MINOR:** New features, backward compatible
- **PATCH:** Bug fixes

Examples:
- `1.0.0` → `1.0.1` (bug fix)
- `1.0.1` → `1.1.0` (new feature)
- `1.1.0` → `2.0.0` (major redesign)

---

## Troubleshooting

### "Repository not found" when pushing
```bash
# Make sure you're using the right GitHub account
gh auth switch -u justin-genies

# Verify remote URL
git remote -v
```

### Large file errors
Binary files (node, ffmpeg, etc.) use Git LFS. If you get size errors:
```bash
git lfs install
git lfs track "KnowledgeTool/Resources/bin/*"
git add .gitattributes
git add KnowledgeTool/Resources/bin/*
```

### Signature verification failed
Make sure you're using the raw key format:
```bash
~/.sparkle-tools/bin/sign_update build/KnowledgeTool-X.Y.Z.zip \
  -f ~/.sparkle-keys/eddsa_private_key_raw
```

### Users not seeing updates
1. Check that `appcast.xml` is pushed to main
2. Verify the download URL in appcast matches the GitHub release asset
3. Check the signature in appcast matches what `sign_update` outputs

---

## Remotes

| Remote | URL | Purpose |
|--------|-----|---------|
| `geniesinc` | github.com/geniesinc/knowledgetool | Production releases |
| `origin` | github.com/rawrjustin/knowledge-tool | Development |

---

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/release.sh` | Automated release script |
| `scripts/setup-sparkle.sh` | One-time key generation |
| `appcast.xml` | Sparkle update feed (commit to repo) |
| `build-app.sh` | Command-line build script |
| `RELEASING.md` | This file |
