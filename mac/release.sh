#!/bin/bash
set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DMG_NAME="Nanomouse-Installer.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# 1. Check gh CLI
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) Not Found."
    echo "   Please install it: brew install gh"
    echo "   And login: gh auth login"
    exit 1
fi

# 2. Check DMG
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found at $DMG_PATH"
    echo "   Please run 'sh mac/build_dmg.sh' first."
    exit 1
fi

# 3. Get Version
VERSION="$1"
if [ -z "$VERSION" ]; then
    read -p "Enter Release Version (e.g. 1.0.0): " VERSION
fi

if [ -z "$VERSION" ]; then
    echo "❌ Version is required."
    exit 1
fi

# Optional: Ensure it starts with v? 
# User requested raw numbers. We will respect the input as-is.
# If they type "1.0.0", tag will be "1.0.0".
# If they type "v1.0.0", tag will be "v1.0.0".

echo "🚀 Preparing Release: $VERSION"

# 4. Create Git Tag
# Check if tag exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "⚠️  Tag $VERSION already exists."
else
    echo "🏷️  Creating Git Tag: $VERSION"
    git tag -a "$VERSION" -m "Release $VERSION"
    git push origin "$VERSION"
fi

# 5. Create GitHub Release
echo "📦 Uploading to GitHub Releases..."

# Title default: "Nanomouse 1.0.0"
TITLE="Nanomouse $VERSION"
NOTES="$2"

if [ -n "$NOTES" ]; then
    echo "📝 Using custom release notes..."
    gh release create "$VERSION" \
        "$DMG_PATH" \
        --title "$TITLE" \
        --notes "$NOTES" \
        --draft
else
    echo "📝 Auto-generating release notes from commits..."
    gh release create "$VERSION" \
        "$DMG_PATH" \
        --title "$TITLE" \
        --generate-notes \
        --draft
fi

echo "✅ Draft Release Created!"
echo "   Go to GitHub to publish it."
