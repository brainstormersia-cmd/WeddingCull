#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "💍 WeddingCull Photographer Ground-Truth Evaluator"
echo "===================================================="

INPUT_DIR=""
KEEPERS_FILE=""
TARGET_COUNT=700
OUTPUT_DIR="artifacts/evaluation"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_DIR="$2"
      shift 2
      ;;
    --keepers)
      KEEPERS_FILE="$2"
      shift 2
      ;;
    --target)
      TARGET_COUNT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$INPUT_DIR" ] || [ ! -d "$INPUT_DIR" ]; then
  echo "❌ Error: --input directory must be provided and must exist."
  echo "Usage: ./scripts/evaluate-wedding.sh --input /path/to/photos --keepers /path/to/keepers.txt --target 700 --output artifacts/eval"
  exit 1
fi

if [ -z "$KEEPERS_FILE" ] || [ ! -f "$KEEPERS_FILE" ]; then
  echo "❌ Error: --keepers file must be provided and must exist."
  echo "Usage: ./scripts/evaluate-wedding.sh --input /path/to/photos --keepers /path/to/keepers.txt --target 700 --output artifacts/eval"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Input wedding shoot: $INPUT_DIR"
echo "Ground-truth keepers: $KEEPERS_FILE"
echo "Target cull count: $TARGET_COUNT"
echo "Output directory: $OUTPUT_DIR"

echo ""
echo "🚀 Running ValidationRunner on photographer shoot..."
swift run ValidationRunner \
  --input "$INPUT_DIR" \
  --keepers "$KEEPERS_FILE" \
  --target "$TARGET_COUNT" \
  --output-dir "$OUTPUT_DIR"

echo ""
echo "===================================================="
echo "✅ Evaluation completed."
echo "Artifacts generated in: $OUTPUT_DIR"
echo "  - $OUTPUT_DIR/selection-ground-truth-report.json"
echo "  - $OUTPUT_DIR/category-report.json"
echo "  - $OUTPUT_DIR/duplicate-burst-report.json"
echo "  - $OUTPUT_DIR/VALIDATION_REPORT.md"
echo "===================================================="
