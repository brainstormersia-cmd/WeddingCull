#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🏗️ Building WeddingCull Release (Universal Binary)"
echo "===================================================="

mkdir -p build/Universal
mkdir -p artifacts

if [ -d "WeddingCull.xcodeproj" ]; then
    echo "Building Universal binary via xcodebuild..."
    xcodebuild build \
        -project WeddingCull.xcodeproj \
        -scheme WeddingCull \
        -configuration Release \
        -destination "generic/platform=macOS" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        CONFIGURATION_BUILD_DIR="$(pwd)/build/Universal" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    EXECUTABLE_PATH="build/Universal/WeddingCull.app/Contents/MacOS/WeddingCull"
else
    echo "Building Universal binary via Swift Package Manager..."
    swift build -c release --triple arm64-apple-macosx
    swift build -c release --triple x86_64-apple-macosx

    mkdir -p build/Universal/WeddingCull.app/Contents/MacOS
    mkdir -p build/Universal/WeddingCull.app/Contents/Resources

    cp Sources/WeddingCullApp/Info.plist build/Universal/WeddingCull.app/Contents/Info.plist

    lipo -create \
        .build/arm64-apple-macosx/release/WeddingCull \
        .build/x86_64-apple-macosx/release/WeddingCull \
        -output build/Universal/WeddingCull.app/Contents/MacOS/WeddingCull

    EXECUTABLE_PATH="build/Universal/WeddingCull.app/Contents/MacOS/WeddingCull"
fi

echo "===================================================="
echo "🔍 Verifying Universal Binary Architectures"
echo "===================================================="
LIPO_INFO=$(lipo -info "$EXECUTABLE_PATH")
echo "$LIPO_INFO"

if [[ "$LIPO_INFO" != *"arm64"* ]] || [[ "$LIPO_INFO" != *"x86_64"* ]]; then
    echo "❌ ERROR: Universal binary is missing one of the required architectures (arm64, x86_64)!"
    echo "Found architectures: $LIPO_INFO"
    exit 1
fi

echo "✅ SUCCESS: Universal binary verified with both arm64 and x86_64."
