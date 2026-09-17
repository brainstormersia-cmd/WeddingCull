#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧪 Running WeddingCull Automated Tests"
echo "===================================================="

ARCH=$(uname -m)
echo "Current Architecture: $ARCH"

export ARTIFACTS_DIR="$(pwd)/artifacts"
mkdir -p "$ARTIFACTS_DIR/screenshots"
mkdir -p "$ARTIFACTS_DIR/reports"

RUN_UNIT=true
RUN_UI=true

for arg in "$@"; do
    case "$arg" in
        --unit-only)
            RUN_UNIT=true
            RUN_UI=false
            ;;
        --ui-only)
            RUN_UNIT=false
            RUN_UI=true
            ;;
    esac
done

if [ "$RUN_UNIT" = true ]; then
    echo "1. Executing Unit & Integration tests via Swift Package Manager..."
    swift test --verbose
fi

if [ "$RUN_UI" = true ]; then
    echo "2. Checking for Xcode UI Test capability..."
    if command -v xcodebuild &>/dev/null && [ -f "WeddingCull.xcodeproj/project.pbxproj" ]; then
        echo "Running UI automation tests via xcodebuild..."
        rm -rf artifacts/WeddingCullUITests.xcresult artifacts/WeddingCullUITests.xcresult.zip
        defaults write com.apple.screensaver idleTime 0 2>/dev/null || true
        CAFF_CMD=""
        if command -v caffeinate &>/dev/null; then
            CAFF_CMD="caffeinate -dimsu"
        fi
        $CAFF_CMD perl -e 'alarm 450; exec @ARGV' xcodebuild test \
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
        echo "✅ UI tests passed successfully."
    else
        echo "ℹ️ Skipping xcodebuild UI test execution (no Xcode project available or not macOS GUI environment)."
    fi
fi

echo "✅ Tests execution finished on $(uname -m)."
