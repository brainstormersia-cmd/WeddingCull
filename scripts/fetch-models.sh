#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "🧠 Model Assets & Provenance for WeddingCull"
echo "===================================================="

MODELS_DIR="models"
mkdir -p "$MODELS_DIR"

PINNED_MOBILECLIP_REVISION="3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947"

echo "Core Vision-based pipeline: BUILT-IN (Apple Vision Framework)"
echo "Target CoreML Image Model: mobileclip_s0_image.mlpackage (pinned revision: $PINNED_MOBILECLIP_REVISION)"
echo "Target CoreML Face Model: MobileFaceNet.mlmodelc"

# Check if model is already downloaded and compiled
if [ -d "$MODELS_DIR/mobileclip_s0_image.mlmodelc" ] || [ -d "$MODELS_DIR/mobileclip_s0_image.mlpackage" ]; then
    echo "✅ MobileCLIP image encoder is already present in $MODELS_DIR."
    if [ ! -d "$MODELS_DIR/mobileclip_s0_image.mlmodelc" ] && command -v xcrun &>/dev/null; then
        echo "⚙️ Compiling Core ML model package to .mlmodelc..."
        xcrun coremlc compile "$MODELS_DIR/mobileclip_s0_image.mlpackage" "$MODELS_DIR" || true
    fi
else
    echo "⬇️ Ensuring Hugging Face download client is available..."
    HF_CMD=""
    if command -v huggingface-cli &>/dev/null; then
        HF_CMD="huggingface-cli"
    elif python3 -m huggingface_hub.cli.download --help &>/dev/null; then
        HF_CMD="python3 -m huggingface_hub.cli.download"
    else
        echo "📦 Installing huggingface_hub CLI..."
        if command -v pip3 &>/dev/null; then
            pip3 install --quiet --break-system-packages "huggingface_hub[cli]" || pip3 install --quiet "huggingface_hub[cli]" || true
        elif command -v pip &>/dev/null; then
            pip install --quiet --break-system-packages "huggingface_hub[cli]" || pip install --quiet "huggingface_hub[cli]" || true
        fi
        if command -v huggingface-cli &>/dev/null; then
            HF_CMD="huggingface-cli"
        elif python3 -m huggingface_hub.cli.download --help &>/dev/null; then
            HF_CMD="python3 -m huggingface_hub.cli.download"
        fi
    fi

    if [ -n "$HF_CMD" ]; then
        echo "Running: $HF_CMD download apple/coreml-mobileclip --revision $PINNED_MOBILECLIP_REVISION --include 'mobileclip_s0_image.mlpackage/*' --local-dir $MODELS_DIR"
        if $HF_CMD download apple/coreml-mobileclip --revision "$PINNED_MOBILECLIP_REVISION" --include "mobileclip_s0_image.mlpackage/*" --local-dir "$MODELS_DIR"; then
            echo "✅ Successfully downloaded MobileCLIP-S0 Image Encoder package."
            if command -v xcrun &>/dev/null; then
                echo "⚙️ Compiling Core ML model package to .mlmodelc..."
                xcrun coremlc compile "$MODELS_DIR/mobileclip_s0_image.mlpackage" "$MODELS_DIR" || true
            fi
        else
            echo "⚠️ Warning: Failed to download Core ML model package from Hugging Face."
        fi
    else
        echo "⚠️ Warning: huggingface-cli could not be installed or executed."
    fi
fi

echo ""
echo "Model Architecture Summary:"
echo "  - Vision Classification: Built-in Apple Vision (VNClassifyImageRequest)"
echo "  - Image Feature Prints: Built-in Apple Vision (VNGenerateImageFeaturePrintRequest)"
echo "  - Advanced Scene Classifier: MobileCLIP-S0 (precalculated text concepts + CoreML image encoder)"
echo "  - Face Recognition: FaceIdentityRecognizer with geometric landmark proportions & CoreML support"
echo "===================================================="
