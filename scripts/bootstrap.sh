#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🚀 Bootstrapping WeddingCull Build Environment"
echo "===================================================="

ARCH=$(uname -m)
OS=$(uname -s)
echo "Operating System: $OS"
echo "Machine Architecture: $ARCH"

if [ "$OS" != "Darwin" ]; then
    echo "⚠️ Warning: Not running on macOS (Darwin). Current OS: $OS"
fi

mkdir -p artifacts/screenshots
mkdir -p artifacts/reports

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Installing xcodegen via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "⚠️ Homebrew not found. XcodeGen must be installed manually."
    fi
fi

if command -v xcodegen &> /dev/null; then
    echo "⚙️ Generating Xcode project from project.yml..."
    xcodegen generate
    echo "✅ WeddingCull.xcodeproj generated successfully."
else
    echo "⚠️ xcodegen not found; SPM package will be used."
fi

echo "✅ Bootstrap complete."
