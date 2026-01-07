#!/bin/bash
set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC_DIR="$PROJECT_ROOT/mac"
GUI_DIR="$MAC_DIR/gui"
INSTALLERS_DIR="$PROJECT_ROOT/installers/mac"
BUILD_DIR="$PROJECT_ROOT/build"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_NAME="Nanomouse-Installer.dmg"
APP_NAME="Nanomouse Configurator.app"
INSTALLER_APP_NAME="Install Configs.app"

# Cleanup
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

echo "🚀 Starting Nanomouse macOS Build..."

# Load Environment Variables from .env if present
if [ -f "$MAC_DIR/.env" ]; then
    echo "📄 Loading environment variables from mac/.env..."
    source "$MAC_DIR/.env"
fi

# 1. Build GUI App
echo "📦 Building SCT GUI..."
cd "$GUI_DIR"
xcodebuild -project SCT.xcodeproj \
           -scheme SCT \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR/SCT-Build" \
           -quiet \
           clean build

# Check if build was successful
GUI_APP_PATH="$BUILD_DIR/SCT-Build/Build/Products/Release/SCT.app"
if [ ! -d "$GUI_APP_PATH" ]; then
    echo "❌ GUI Build Failed!"
    exit 1
fi

echo "✅ GUI Build Success!"

# 1.1 Code Sign GUI App (Hardened Runtime)
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    echo "🔏 Signing App with identity: $CODE_SIGN_IDENTITY"
    codesign --force --options runtime --deep --sign "$CODE_SIGN_IDENTITY" "$GUI_APP_PATH"
else
    echo "⚠️  CODE_SIGN_IDENTITY not set. Skipping App signing."
    echo "    (App will not run on other machines without signing)"
fi

# 2. Build Installer Wrapper (AppleScript)
echo "📜 Building Installer Wrapper..."
osacompile -o "$STAGING_DIR/$INSTALLER_APP_NAME" "$INSTALLERS_DIR/Nanomouse Installer.applescript"

# Copy install_core.sh content into the app bundle resources if needed by the applescript
mkdir -p "$STAGING_DIR/$INSTALLER_APP_NAME/Contents/Resources"
cp "$INSTALLERS_DIR/install_core.sh" "$STAGING_DIR/$INSTALLER_APP_NAME/Contents/Resources/"
chmod +x "$STAGING_DIR/$INSTALLER_APP_NAME/Contents/Resources/install_core.sh"

# 3. Assemble DMG Content
echo "📂 Assembling DMG Content..."

# Copy GUI App
cp -R "$GUI_APP_PATH" "$STAGING_DIR/$APP_NAME"

# Copy Readme
cp "$PROJECT_ROOT/README.md" "$STAGING_DIR/README.md"
# Create a simple instruction text
echo "1. Drag 'Nanomouse Configurator.app' to Applications to install the GUI tool." > "$STAGING_DIR/使用说明.txt"
echo "2. Double click 'Install Configs.app' to assist with Rime configuration setup." >> "$STAGING_DIR/使用说明.txt"

# Copy Configs
cp -R "$PROJECT_ROOT/shared" "$STAGING_DIR/shared"
cp -R "$PROJECT_ROOT/configs" "$STAGING_DIR/configs"

# 4. Create DMG
echo "💿 Creating DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME"
# Remove existing DMG
rm -f "$DMG_PATH"

# Create DMG
hdiutil create -volname "Nanomouse Installer" \
               -srcfolder "$STAGING_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

# 5. Sign DMG
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    echo "🔏 Signing DMG..."
    codesign --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
else
    echo "⚠️  CODE_SIGN_IDENTITY not set. Skipping DMG signing."
fi

# 6. Notarize DMG
if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    echo "🛡️  Notarizing DMG (Profile: $NOTARY_KEYCHAIN_PROFILE)..."
    echo "    This may take a few minutes..."
    
    xcrun notarytool submit "$DMG_PATH" \
                     --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
                     --wait
    
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    echo "✅ Notarization Complete!"
    
    echo "🔍 Verifying Signature..."
    spctl --assess --verbose=4 --type install "$DMG_PATH"
else
    echo "⚠️  NOTARY_KEYCHAIN_PROFILE not set. Skipping Notarization."
fi

echo "🎉 Build Complete!"
echo "Parsed DMG is at: $DMG_PATH"
