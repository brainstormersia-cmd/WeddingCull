#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧠 Model Assets & Provenance for WeddingCull"
echo "===================================================="

MODELS_DIR="models"
mkdir -p "$MODELS_DIR"

echo "Core Vision-based pipeline: BUILT-IN (Apple Vision Framework)"
echo "Target CoreML Image Model: mobileclip_s0_image.mlpackage"
echo "Target CoreML Face Model: MobileFaceNet.mlmodelc"

# Check if model is already downloaded
if [ -d "$MODELS_DIR/mobileclip_s0_image.mlmodelc" ] || [ -d "$MODELS_DIR/mobileclip_s0_image.mlpackage" ]; then
    echo "✅ MobileCLIP image encoder is already present in $MODELS_DIR."
else
    echo "⬇️ Attempting download of MobileCLIP-S0 Image Encoder from Apple CoreML repo..."
    MODEL_URL="https://huggingface.co/apple/coreml-mobileclip/resolve/main/mobileclip_s0_image.mlpackage"
    
    # Optional download using curl with 10s timeout
    if curl -sLf --connect-timeout 10 "$MODEL_URL" -o "$MODELS_DIR/mobileclip_s0_image.mlpackage" 2>/dev/null; then
        echo "✅ Downloaded MobileCLIP-S0 Image Encoder."
        if command -v xcrun &>/dev/null; then
            echo "⚙️ Compiling Core ML model package to .mlmodelc..."
            xcrun coremlc compile "$MODELS_DIR/mobileclip_s0_image.mlpackage" "$MODELS_DIR" || true
        fi
    else
        echo "ℹ️ Note: CoreML remote weights not downloaded (network unreachable or skipped)."
        echo "ℹ️ WeddingCull will automatically and seamlessly use native Apple Vision scene classification."
    fi
fi

echo ""
echo "Model Architecture Summary:"
echo "  - Vision Classification: Built-in Apple Vision (VNClassifyImageRequest)"
echo "  - Image Feature Prints: Built-in Apple Vision (VNGenerateImageFeaturePrintRequest)"
echo "  - Advanced Scene Classifier: MobileCLIP-S0 (precalculated text concepts + CoreML image encoder)"
echo "  - Face Recognition: FaceIdentityRecognizer with biometric landmarks & CoreML support"
echo "===================================================="
