#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🏗️ Building WeddingCull Universal Binary (arm64 + x86_64)"
echo "===================================================="

mkdir -p build/Universal/WeddingCull.app/Contents/MacOS
mkdir -p build/Universal/WeddingCull.app/Contents/Resources
mkdir -p artifacts

echo "Compiling arm64 slice..."
swift build -c release --triple arm64-apple-macosx --product WeddingCull

echo "Compiling x86_64 slice..."
swift build -c release --triple x86_64-apple-macosx --product WeddingCull

echo "Creating Universal Fat Binary via lipo..."
lipo -create \
    .build/arm64-apple-macosx/release/WeddingCull \
    .build/x86_64-apple-macosx/release/WeddingCull \
    -output build/Universal/WeddingCull.app/Contents/MacOS/WeddingCull

cp Sources/WeddingCullApp/Info.plist build/Universal/WeddingCull.app/Contents/Info.plist

echo "===================================================="
echo "🔍 Verifying Universal Binary Architectures"
echo "===================================================="
LIPO_INFO=$(lipo -info build/Universal/WeddingCull.app/Contents/MacOS/WeddingCull)
echo "$LIPO_INFO"

if [[ "$LIPO_INFO" != *"arm64"* ]] || [[ "$LIPO_INFO" != *"x86_64"* ]]; then
    echo "❌ ERROR: Universal binary is missing one of the required architectures!"
    exit 1
fi

echo "✅ SUCCESS: Universal binary contains both arm64 and x86_64."
