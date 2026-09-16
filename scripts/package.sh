#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "📦 Packaging WeddingCull v1.0.0"
echo "===================================================="

APP_PATH="build/Universal/WeddingCull.app"
ARTIFACTS_DIR="artifacts"
mkdir -p "$ARTIFACTS_DIR"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH does not exist. Run build-release.sh first."
    exit 1
fi

ZIP_PATH="$ARTIFACTS_DIR/WeddingCull-1.0.0-universal.zip"
echo "Creating ZIP archive: $ZIP_PATH..."
(cd build/Universal && zip -q -r -y "../../$ZIP_PATH" WeddingCull.app)

echo "✅ Created $ZIP_PATH ($(du -sh "$ZIP_PATH" | cut -f1))"

DMG_PATH="$ARTIFACTS_DIR/WeddingCull-1.0.0.dmg"
if command -v hdiutil &> /dev/null; then
    echo "Creating DMG disk image: $DMG_PATH..."
    rm -f "$DMG_PATH"
    hdiutil create -volname "WeddingCull" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH" || echo "⚠️ Could not generate DMG, proceeding with ZIP."
    if [ -f "$DMG_PATH" ]; then
        echo "✅ Created $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
    fi
else
    echo "ℹ️ hdiutil not available, skipping DMG."
fi

echo "===================================================="
echo "✅ Packaging complete."
