#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🚀 Bootstrapping WeddingCull Build Environment"
echo "===================================================="

ARCH=$(uname -m)
OS=$(uname -s)
echo "Operating System: $OS"
echo "Machine Architecture: $ARCH"

mkdir -p artifacts/screenshots
mkdir -p artifacts/reports

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Checking Homebrew for xcodegen..."
    if command -v brew &> /dev/null; then
        brew install xcodegen || true
    fi
fi

if command -v xcodegen &> /dev/null; then
    echo "⚙️ Generating Xcode project from project.yml..."
    xcodegen generate || true

    # Fix objectVersion if generated with format 77 for compatibility with Xcode 15/16
    if [ -f "WeddingCull.xcodeproj/project.pbxproj" ]; then
        echo "🔧 Ensuring Xcode project compatibility..."
        sed -i '' 's/objectVersion = [0-9][0-9]*;/objectVersion = 56;/g' WeddingCull.xcodeproj/project.pbxproj || true
    fi
fi

# Fetch verified test datasets & genuine RAW fixtures
if [ -f "scripts/fetch-test-datasets.sh" ]; then
    echo "📦 Fetching verified public datasets & test fixtures..."
    chmod +x scripts/fetch-test-datasets.sh
    ./scripts/fetch-test-datasets.sh || true
fi

echo "✅ Bootstrap complete."
