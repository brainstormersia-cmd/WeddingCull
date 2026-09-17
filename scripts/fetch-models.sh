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
    echo "⬇️ Attempting download of MobileCLIP-S0 Image Encoder via huggingface-cli..."
    HF_CMD=""
    if command -v huggingface-cli &>/dev/null; then
        HF_CMD="huggingface-cli"
    elif python3 -m huggingface_hub.cli.download --help &>/dev/null; then
        HF_CMD="python3 -m huggingface_hub.cli.download"
    fi

    if [ -n "$HF_CMD" ]; then
        echo "Running: $HF_CMD apple/coreml-mobileclip --include 'mobileclip_s0_image.mlpackage/*' --local-dir $MODELS_DIR"
        if $HF_CMD download apple/coreml-mobileclip --include "mobileclip_s0_image.mlpackage/*" --local-dir "$MODELS_DIR" 2>/dev/null || \
           $HF_CMD apple/coreml-mobileclip --include "mobileclip_s0_image.mlpackage/*" --local-dir "$MODELS_DIR" 2>/dev/null; then
            echo "✅ Downloaded MobileCLIP-S0 Image Encoder package."
            if command -v xcrun &>/dev/null; then
                echo "⚙️ Compiling Core ML model package to .mlmodelc..."
                xcrun coremlc compile "$MODELS_DIR/mobileclip_s0_image.mlpackage" "$MODELS_DIR" || true
            fi
        else
            echo "ℹ️ Note: CoreML weights download skipped (network unreachable or rate-limited)."
            echo "ℹ️ WeddingCull will automatically and seamlessly use native Apple Vision scene classification."
        fi
    else
        echo "ℹ️ Note: huggingface-cli not installed. Using native Apple Vision scene classification."
    fi
fi

echo ""
echo "Model Architecture Summary:"
echo "  - Vision Classification: Built-in Apple Vision (VNClassifyImageRequest)"
echo "  - Image Feature Prints: Built-in Apple Vision (VNGenerateImageFeaturePrintRequest)"
echo "  - Advanced Scene Classifier: MobileCLIP-S0 (precalculated text concepts + CoreML image encoder)"
echo "  - Face Recognition: FaceIdentityRecognizer with biometric landmarks & CoreML support"
echo "===================================================="
