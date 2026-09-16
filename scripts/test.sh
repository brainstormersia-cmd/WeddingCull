#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧪 Running WeddingCull Automated Tests"
echo "===================================================="

ARCH=$(uname -m)
echo "Current Architecture:"
uname -m

mkdir -p artifacts

echo "Executing tests via Swift Package Manager..."
swift test --verbose

echo "✅ All tests executed and passed successfully on $(uname -m)."
