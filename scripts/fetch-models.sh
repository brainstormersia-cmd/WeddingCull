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
    PYTHON_CMD="python3"
    if ! command -v python3 &>/dev/null; then
        PYTHON_CMD="python"
    fi

    if ! $PYTHON_CMD -c "import huggingface_hub" &>/dev/null; then
        echo "📦 Installing huggingface_hub..."
        if command -v pip3 &>/dev/null; then
            pip3 install --quiet --break-system-packages "huggingface_hub" || pip3 install --quiet "huggingface_hub" || true
        elif command -v pip &>/dev/null; then
            pip install --quiet --break-system-packages "huggingface_hub" || pip install --quiet "huggingface_hub" || true
        fi
    fi

    DOWNLOAD_SUCCESS=false
    if $PYTHON_CMD -c "import huggingface_hub" &>/dev/null; then
        echo "Running huggingface_hub snapshot_download for apple/coreml-mobileclip@$PINNED_MOBILECLIP_REVISION..."
        if $PYTHON_CMD -c '
from huggingface_hub import snapshot_download
import sys
try:
    snapshot_download(
        repo_id="apple/coreml-mobileclip",
        revision="'"$PINNED_MOBILECLIP_REVISION"'",
        allow_patterns=["mobileclip_s0_image.mlpackage/*"],
        local_dir="'"$MODELS_DIR"'"
    )
    print("✅ Successfully downloaded MobileCLIP-S0 Image Encoder via huggingface_hub.")
except Exception as e:
    print(f"Download error: {e}", file=sys.stderr)
    sys.exit(1)
'; then
            DOWNLOAD_SUCCESS=true
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" != "true" ]; then
        if command -v hf &>/dev/null; then
            echo "Running: hf download apple/coreml-mobileclip --revision $PINNED_MOBILECLIP_REVISION --include 'mobileclip_s0_image.mlpackage/*' --local-dir $MODELS_DIR"
            if hf download apple/coreml-mobileclip --revision "$PINNED_MOBILECLIP_REVISION" --include "mobileclip_s0_image.mlpackage/*" --local-dir "$MODELS_DIR"; then
                DOWNLOAD_SUCCESS=true
            fi
        elif command -v huggingface-cli &>/dev/null; then
            echo "Running: huggingface-cli download apple/coreml-mobileclip --revision $PINNED_MOBILECLIP_REVISION --include 'mobileclip_s0_image.mlpackage/*' --local-dir $MODELS_DIR"
            if huggingface-cli download apple/coreml-mobileclip --revision "$PINNED_MOBILECLIP_REVISION" --include "mobileclip_s0_image.mlpackage/*" --local-dir "$MODELS_DIR"; then
                DOWNLOAD_SUCCESS=true
            fi
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" = "true" ]; then
        echo "✅ MobileCLIP package ready."
        if command -v xcrun &>/dev/null; then
            echo "⚙️ Compiling Core ML model package to .mlmodelc..."
            xcrun coremlc compile "$MODELS_DIR/mobileclip_s0_image.mlpackage" "$MODELS_DIR" || true
        fi
    else
        echo "⚠️ Warning: Could not download Core ML model package from Hugging Face."
    fi
fi

echo ""
echo "Model Architecture Summary:"
echo "  - Vision Classification: Built-in Apple Vision (VNClassifyImageRequest)"
echo "  - Image Feature Prints: Built-in Apple Vision (VNGenerateImageFeaturePrintRequest)"
echo "  - Advanced Scene Classifier: MobileCLIP-S0 (precalculated text concepts + CoreML image encoder)"
echo "  - Face Recognition: FaceIdentityRecognizer with geometric landmark proportions & CoreML support"
echo "===================================================="
