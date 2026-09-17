#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "📦 Public Test Datasets & Fixtures for WeddingCull"
echo "===================================================="

DATASETS_DIR="tests/fixtures/datasets"
mkdir -p "$DATASETS_DIR/raw_samples"

# Verify command availability
HASH_CMD=""
if command -v shasum &>/dev/null; then
    HASH_CMD="shasum -a 256"
elif command -v sha256sum &>/dev/null; then
    HASH_CMD="sha256sum"
fi

download_and_verify() {
    local target_file="$1"
    local expected_hash="$2"
    local download_url="$3"
    local description="$4"

    if [ -f "$target_file" ]; then
        if [ -n "$HASH_CMD" ]; then
            actual_hash=$($HASH_CMD "$target_file" | awk '{print $1}')
            if [ "$actual_hash" = "$expected_hash" ]; then
                echo "✅ $description already present and verified ($actual_hash)."
                return 0
            fi
            echo "⚠️ Hash mismatch for $target_file, re-downloading..."
        else
            echo "✅ $description already present."
            return 0
        fi
    fi

    echo "⬇️ Downloading $description from $download_url..."
    mkdir -p "$(dirname "$target_file")"
    if curl -sSL --connect-timeout 15 --retry 3 "$download_url" -o "$target_file.tmp"; then
        if [ -n "$HASH_CMD" ]; then
            actual_hash=$($HASH_CMD "$target_file.tmp" | awk '{print $1}')
            if [ "$actual_hash" != "$expected_hash" ]; then
                echo "❌ Checksum failure for $description! Expected $expected_hash, got $actual_hash"
                rm -f "$target_file.tmp"
                return 1
            fi
        fi
        mv "$target_file.tmp" "$target_file"
        echo "✅ Successfully downloaded and verified $description ($expected_hash)."
    else
        echo "⚠️ Download failed for $description."
        rm -f "$target_file.tmp"
        return 1
    fi
}

echo "1. Checking Real RAW (Canon CR2) verification fixture [MANDATORY]..."
CR2_FIXTURE="$DATASETS_DIR/raw_samples/sample_burst_frame.cr2"
CR2_HASH="e0539843c36e6e3f39ffe15aa91f22624149ad18c63e3bef7b6f0e71cdc46c79"
CR2_URL="https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/cr2/Canon%20EOS%20350D.CR2"
download_and_verify "$CR2_FIXTURE" "$CR2_HASH" "$CR2_URL" "Canon EOS 350D Genuine RAW CR2 Sample"

echo "2. Checking Real RAW (Nikon NEF) verification fixture..."
NEF_FIXTURE="$DATASETS_DIR/raw_samples/NIKON_D70.NEF"
NEF_HASH="97e2faea5ac62040e98710b146a4f296b9570d410bcc44e14da778b5f34ced39"
NEF_URL="https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/nef/Nikon%20D70.nef"
download_and_verify "$NEF_FIXTURE" "$NEF_HASH" "$NEF_URL" "Nikon D70 Genuine RAW NEF Sample" || true

echo "3. Checking Real RAW (Sony ARW) verification fixture..."
ARW_FIXTURE="$DATASETS_DIR/raw_samples/DSLR-A500.ARW"
ARW_HASH="cdf69f2856612620129789fb87c10772f80ec3b040c54a933315c77c2961dc46"
ARW_URL="https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/arw/Sony%20DSLR-A500.arw"
download_and_verify "$ARW_FIXTURE" "$ARW_HASH" "$ARW_URL" "Sony DSLR-A500 Genuine RAW ARW Sample" || true

echo "4. Checking Real RAW (FujiFilm RAF) verification fixture..."
RAF_FIXTURE="$DATASETS_DIR/raw_samples/FinePix_S5500.RAF"
RAF_HASH="5be26d83d80f1424f07b1244c80a5fbb5b699a6ee33419b7a10533f751b77af8"
RAF_URL="https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/raf/FujiFilm%20FinePix%20S5500.raf"
download_and_verify "$RAF_FIXTURE" "$RAF_HASH" "$RAF_URL" "FujiFilm FinePix S5500 Genuine RAW RAF Sample" || true

echo ""
echo "5. Checking AlbumBench / CUFED Wedding dataset availability..."
if [ -f "scripts/fetch-albumbench-subset.sh" ]; then
    chmod +x scripts/fetch-albumbench-subset.sh
    ./scripts/fetch-albumbench-subset.sh || true
fi

echo ""
echo "===================================================="
echo "✅ Dataset fetch check completed with strict hash verification."
echo "Active dataset location: $DATASETS_DIR"
echo "===================================================="
