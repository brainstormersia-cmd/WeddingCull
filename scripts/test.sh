#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧪 Running WeddingCull Automated Tests"
echo "===================================================="

ARCH=$(uname -m)
echo "Architecture: $ARCH"
uname -m

mkdir -p artifacts

if [ -d "WeddingCull.xcodeproj" ]; then
    echo "Running tests via xcodebuild..."
    xcodebuild test \
        -project WeddingCull.xcodeproj \
        -scheme WeddingCullTests \
        -destination "platform=macOS" \
        -resultBundlePath artifacts/WeddingCullTests.xcresult \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    echo "Running integration tests..."
    xcodebuild test \
        -project WeddingCull.xcodeproj \
        -scheme WeddingCullIntegrationTests \
        -destination "platform=macOS" \
        -resultBundlePath artifacts/WeddingCullIntegrationTests.xcresult \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
else
    echo "Running tests via Swift Package Manager..."
    swift test --verbose
fi

echo "✅ All tests passed successfully."
