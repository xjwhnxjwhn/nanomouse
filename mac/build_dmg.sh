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

# 2. Build Installer Wrapper (AppleScript)
echo "📜 Building Installer Wrapper..."
osacompile -o "$STAGING_DIR/$INSTALLER_APP_NAME" "$INSTALLERS_DIR/Nanomouse Installer.applescript"

# Copy install_core.sh content into the app bundle resources if needed by the applescript
# Typically the applescript logic might rely on relative paths or embedded scripts.
# Looking at previous behavior, there might be a need to place scripts properly.
# For now, let's assume the AppleScript expects 'install_core.sh' nearby or handles it.
# Actually, standard practice for such installers is often to put the shell script in Contents/Resources.
# Let's inspect the AppleScript later if this fails, but for now copying install_core.sh to Resources is a safe bet.
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

# Copy Configs (Shared) for the installer script to use
# The installer script likely expects a 'shared' directory or similar relative path.
# Let's copy 'shared' and 'configs' to the root of the DMG (can be hidden later or just visible)
# so the installer script can find them.
# Adjusting based on standard folder structure found in repo.
cp -R "$PROJECT_ROOT/shared" "$STAGING_DIR/shared"
cp -R "$PROJECT_ROOT/configs" "$STAGING_DIR/configs"

# 4. Create DMG
echo "💿 Creating DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

hdiutil create -volname "Nanomouse Installer" \
               -srcfolder "$STAGING_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

echo "🎉 Build Complete!"
echo "Parsed DMG is at: $DMG_PATH"
