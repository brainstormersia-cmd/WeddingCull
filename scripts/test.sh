#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧪 Running WeddingCull Automated Tests"
echo "===================================================="

ARCH=$(uname -m)
echo "Current Architecture: $ARCH"

mkdir -p artifacts/screenshots
mkdir -p artifacts/reports

echo "1. Executing Unit & Integration tests via Swift Package Manager..."
swift test --verbose

echo "2. Checking for Xcode UI Test capability..."
if command -v xcodebuild &>/dev/null && [ -f "WeddingCull.xcodeproj/project.pbxproj" ]; then
    echo "Running UI automation tests via xcodebuild..."
    rm -rf artifacts/WeddingCullUITests.xcresult artifacts/WeddingCullUITests.xcresult.zip
    perl -e 'alarm 450; exec @ARGV' xcodebuild test \
        -project WeddingCull.xcodeproj \
        -scheme WeddingCull \
        -only-testing:WeddingCullUITests \
        -destination "platform=macOS" \
        -resultBundlePath artifacts/WeddingCullUITests.xcresult \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
    if [ -d "artifacts/WeddingCullUITests.xcresult" ]; then
        echo "Compressing xcresult for artifact upload..."
        (cd artifacts && zip -q -r WeddingCullUITests.xcresult.zip WeddingCullUITests.xcresult && rm -rf WeddingCullUITests.xcresult) || true
    fi
else
    echo "ℹ️ Skipping xcodebuild UI test execution (no Xcode project available)."
fi

echo "✅ Tests execution finished on $(uname -m)."
