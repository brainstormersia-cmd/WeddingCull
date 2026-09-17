# Open-Source Prior-Art Research & Engineering Evaluation

**Document Status**: Production Reference  
**Evaluation Date**: September 2026  
**Target Application**: WeddingCull (100% Local macOS Wedding Photo Culling)  
**Primary Target Platform**: Intel Mac (x86_64, macOS 13+) + Apple Silicon (arm64, macOS 13+)

---

## 1. Executive Summary & Licensing Rules

WeddingCull aims to automate the initial culling of ~1,500 raw/jpeg wedding photographs down to ~700 diverse, high-quality keepers while preserving 100% local privacy, zero cloud dependencies, and fluid native macOS performance.

### Licensing Policy & Boundaries
1. **Permissive Code (MIT / Apache-2.0)**: Algorithmic concepts and architectural patterns from MIT or Apache-2.0 projects (e.g., `pixcull`, `shutter-cull`, `photo-manager`, `apertureflow`, `Photo-Curator`) may be adapted into native Swift/Core ML/Accelerate code.
2. **Copyleft Code (AGPL-3.0 / GPL)**: Code from AGPL/GPL projects (notably `nielsfranke/Cullimingo`) **must NOT be copied** into WeddingCull in any form. Only high-level UX flows and keyboard navigation conventions may be studied as architectural prior art.
3. **Model Weights Separation**: A repository licensed under MIT does **NOT** grant MIT rights to downloaded neural weights. Model weights (e.g., InsightFace/ArcFace non-commercial licenses, LAION CLIP weights, Apple ML Research TOU) carry separate terms and must be audited individually. WeddingCull relies primarily on Apple Vision framework and officially distributed Core ML packages (MobileCLIP with Apple ML Research TOU).

---

## 2. Project-by-Project Technical Breakdown

### 2.1 `ncoevoet/facet`
* **Repository**: `https://github.com/ncoevoet/facet`
* **Inspected Commit**: `5b4b29b07f0ce71e21a0579a3957b0253f243201` (2026-09-15)
* **Code License**: MIT (formerly custom/NOASSERTION in index, MIT declared in repository)
* **Model Weights License**: Mixed: YuNet (Apache 2.0), ONNX face models, InsightFace/RetinaFace (non-commercial research only).
* **Intel / macOS Compatibility**: Runs on Intel x86_64 macOS via Python/FastAPI backend; CPU-only execution supported.
* **Runtime Dependencies**: Python 3.10+, FastAPI, Angular 21 frontend, OpenCV, libraw/darktable.
* **Relevant Algorithms**:
  * 9-dimensional photo scoring (aesthetic, composition, face quality, eye sharpness, technical sharpness, color, exposure, saliency, dynamic range).
  * Category-dependent scoring weights (30+ genres).
  * Sequence protection (`--detect-sequences`, `--detect-panoramas`): exposure brackets and HDR panoramas are kept intact and never collapsed to a single winner.
  * Blink detection and chronological scene segmentation by capture-time deltas.
* **What WeddingCull Adapts**:
  * **Sequence Protection Concept**: Burst detection must not accidentally collapse deliberate exposure brackets or panoramic sweeps.
  * **Blink Detection heuristic**: Eye-openness ratio integrated into burst winner selection.
* **What WeddingCull Rejects**:
  * Python/Angular stack: WeddingCull is a native Swift/SwiftUI app with zero runtime web servers or Python processes.
  * Complex 30+ genre ontology: Wedding shoots require specific wedding taxonomy (12 categories), not general-purpose categorization.
* **License Risk**: Low for architecture; high if importing InsightFace weights (non-commercial clause).

---

### 2.2 `ChrisChen667788/pixcull`
* **Repository**: `https://github.com/ChrisChen667788/pixcull`
* **Inspected Commit**: `5b8482a07c07d7da9f03a68d88e6a2fcdc4ce923` (2026-09-12)
* **Code License**: MIT
* **Model Weights License**: Non-commercial for InsightFace/ArcFace face embeddings; CC-BY-NC for specific aesthetic weights.
* **Intel / macOS Compatibility**: Supports Apple Silicon & Intel macOS (via ONNX runtime / PyTorch CPU).
* **Runtime Dependencies**: Python 3.11+, PyTorch/ONNX, OpenCV, exiftool.
* **Relevant Algorithms**:
  * 6-axis photographic rubric.
  * Learned face embeddings + DBSCAN clustering.
  * Synchronized 1:1 A/B inspection.
  * Burst-peak ranking vs. auto-rejection separation.
* **What WeddingCull Adapts**:
  * **Crucial Product Lesson: Burst Ranking != Automatic Rejection**: Early PixCull versions automatically demoted burst losers, which frustrated photographers when valid secondary frames were culled. WeddingCull recommends a burst winner, but retains secondary frames as `.alternative` rather than `.rejected`.
  * Synchronized 1:1 loupe compare across burst frames.
* **What WeddingCull Rejects**:
  * External python runtime; bundling unvetted ArcFace models with ambiguous commercial rights.
* **License Risk**: Python code is MIT; bundled weights risk non-commercial restrictions if reused directly.

---

### 2.3 `keivanmalhani/shutter-cull`
* **Repository**: `https://github.com/keivanmalhani/shutter-cull`
* **Inspected Commit**: `2f67080496aa48f6c44a72343bf519c6646e897a` (2026-09-02)
* **Code License**: MIT
* **Model Weights License**: YuNet (Apache 2.0).
* **Intel / macOS Compatibility**: 100% CPU-friendly, excellent performance on Intel x86_64.
* **Runtime Dependencies**: Python 3.11+, OpenCV, exiftool.
* **Relevant Algorithms**:
  * Embedded RAW preview extraction without slow full demosaicing.
  * Burst clustering: EXIF timestamp proximity (chained 2s window) confirmed by perceptual hash similarity (prevents grouping when camera pans to new subject).
  * Laplacian variance sharpness + eye openness.
  * **Shoot-Relative Percentile Ranking**: Normalizes metrics within the current scan rather than applying rigid global thresholds (e.g., handles dark dance floor vs. bright beach).
  * Pick/Reject XMP sidecars without modifying original raw files.
* **What WeddingCull Adapts**:
  * **Shoot-Relative Robust Normalization**: WeddingCull's `RobustNormalizer` directly employs IQR/median shoot-relative scaling inspired by this approach.
  * Timestamp + pHash dual-condition burst grouping.
  * Safe non-destructive XMP export (Picks -> 5-star/Green, Rejects -> 1-star/Red).
* **What WeddingCull Rejects**:
  * Hard dependency on external `exiftool` CLI binary (WeddingCull writes standard XMP sidecars natively using Foundation XML).
* **License Risk**: None (pure MIT code, Apache 2.0 YuNet).

---

### 2.4 `itsaldrincr/photo-manager`
* **Repository**: `https://github.com/itsaldrincr/photo-manager`
* **Inspected Commit**: `b375a78030a646aa81b1c854ca87a648164ab9d3` (2026-08-29)
* **Code License**: MIT
* **Model Weights License**: LAION (CC-BY 4.0), DINOv2 (Apache 2.0), mlx-vlm weights (various permissive/research).
* **Intel / macOS Compatibility**: Apple Silicon optimized; heavy stages (mlx-vlm) fail on Intel x86_64.
* **Runtime Dependencies**: Python 3.11+, PyTorch, Apple MLX (Silicon-only), MediaPipe.
* **Relevant Algorithms**:
  * Cascading pipeline architecture:
    * Stage 1: Classical cheap filters (blur, exposure, duplicates, bursts).
    * Stage 2: Neural IQA scoring & composition.
    * Stage 3: Expensive VLM tiebreaker only for ambiguous photos.
    * Stage 4: Diversity & narrative flow curation.
* **What WeddingCull Adapts**:
  * **Progressive Compute Expenditure**: Never run heavy neural models on images already eliminated by technical failures (e.g., severe blur, extreme under/over exposure) or exact duplicates.
* **What WeddingCull Rejects**:
  * Heavy VLM tiebreaker requiring 16 GB unified RAM and MLX (incompatible with Intel target).
* **License Risk**: MIT code is safe; VLM weights are too heavy for distribution.

---

### 2.5 `kotyzap/Photo-Curator`
* **Repository**: `https://github.com/kotyzap/Photo-Curator`
* **Inspected Commit**: `1cb56a07a9ed3bff7e3d3f93a9305c31d1cd6e52` (2026-09-13)
* **Code License**: MIT
* **Model Weights License**: No weights; classical CV heuristics.
* **Intel / macOS Compatibility**: Fully compatible with Intel x86_64 and Apple Silicon.
* **Runtime Dependencies**: Python 3.9+, rawpy, imagehash, OpenCV.
* **Relevant Algorithms**:
  * RAW + JPEG pairing with embedded preview extraction.
  * Contrast-normalized Laplacian sharpness.
  * dHash perceptual hashing + ORB keypoint matching for burst verification.
* **What WeddingCull Adapts**:
  * Embedded preview priority: ImageIO `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`.
  * Verification that visual similarity holds across burst intervals.
* **What WeddingCull Rejects**:
  * Browser/Flask architecture.
* **License Risk**: None.

---

### 2.6 `ildrm/apertureflow`
* **Repository**: `https://github.com/ildrm/apertureflow`
* **Inspected Commit**: `3e5f09b89089f8e6b2425fc038f8777613ff91eb` (2026-07-29)
* **Code License**: MIT
* **Model Weights License**: Optional ONNX models.
* **Intel / macOS Compatibility**: Universal macOS binary supported via Tauri / Rust backend.
* **Runtime Dependencies**: Tauri 2, Rust, React, TypeScript, SQLite.
* **Relevant Algorithms**:
  * CPU-first architecture: fast baseline heuristics allow the app to function even if neural models fail to load.
  * SQLite catalog for persistent session states and quick reopening.
  * Non-destructive editing and sidecar metadata.
* **What WeddingCull Adapts**:
  * **Graceful Degradation Rule**: If MobileCLIP Core ML model is missing or fails to load, WeddingCull cleanly falls back to Apple Vision scene classification without crashing or blocking the workflow.
* **What WeddingCull Rejects**:
  * Multi-language web stack (Tauri/React) in favor of 100% native Swift/SwiftUI.
* **License Risk**: None.

---

### 2.7 `nielsfranke/Cullimingo`
* **Repository**: `https://github.com/nielsfranke/Cullimingo`
* **Inspected Commit**: `9085ac8c2ca750928070ad3a6840261e9bdb3935` (2026-08-19)
* **Code License**: AGPL-3.0
* **Model Weights License**: N/A (rule-based and metadata-driven culler).
* **Intel / macOS Compatibility**: Cross-platform (macOS x86_64/arm64, Linux via Flutter).
* **Runtime Dependencies**: Flutter 3.44, Dart 3.12, libraw.
* **Relevant UX & Architectural Concepts**:
  * High-performance virtualized grid with immediate keyboard culling (1/2/3/Space).
  * 2-up / n-up synchronized comparative view.
  * Non-blocking background export and neighbor prefetching.
* **What WeddingCull Adapts (CONCEPTUAL ONLY)**:
  * Keyboard-first culling paradigm (`1` = Select, `2` = Alternative, `3` = Reject, `Space` = Quick Preview, `Enter` = Burst Loupe).
  * Asynchronous prefetching of neighboring thumbnails.
* **CRITICAL LEGAL NOTICE**:
  * **DO NOT COPY ANY CODE FROM CULLIMINGO**. Cullimingo is licensed under AGPL-3.0. Incorporating Cullimingo code into WeddingCull would impose AGPL copyleft obligations. All WeddingCull implementations are 100% clean-room Swift/SwiftUI code.
* **License Risk**: Very high if copied. Zero if kept strictly as black-box behavioral inspiration.

---

### 2.8 Additional Maintained Projects Evaluated
* **`cfelicio/ShotSieve`** (`b4db20b3acdaa2ccb8dd9532d7b07eb37fa14249`, 2026-09-17): Local AI culling comparing models. Useful reference for side-by-side model benchmarking.
* **`prime-radiant-inc/teststrip`** (`c56f2d301c831da41a564adbf965f0b6d4508723`, 2026-09-14): Apache-2.0 macOS native catalog-first culling tool. Reaffirms the necessity of non-destructive catalog/session persistence.

---

## 3. Synthesis: WeddingCull Architectural Blueprint

From the prior-art analysis, WeddingCull adopts the following concrete technical decisions:

1. **Cascading Intel-Friendly Pipeline**:
   * *Stage 1*: Embedded ImageIO preview generation (320px thumb / 1000px preview) + Laplacian sharpness + Exposure analysis.
   * *Stage 2*: Temporal clustering (2s window) + dHash / FeaturePrint duplicate check.
   * *Stage 3*: Apple Vision Face landmarks + eye openness ratio.
   * *Stage 4*: Zero-shot MobileCLIP classification (Intel CPU+GPU, Apple Silicon ANE), falling back gracefully to Vision Scene Classification if unavailable.
   * *Stage 5*: Shoot-relative normalization (median/IQR scaling) + MMR diversity selection.

2. **Burst Discretion vs. Blanket Rejection**:
   * In a burst, the highest-scoring frame is designated as `winner` (`isBurstWinner = true`, suggested `.selected`), while other frames are placed in `.alternative` rather than auto-rejected as `.rejected`.

3. **Non-Destructive Editorial XMP Export**:
   * Photographers retain complete editorial authority: XMP sidecars map `.selected` to 5-star/Green (Pick), `.alternative` to 3-star/Yellow, and `.rejected` to 1-star/Red. AI numerical scores stay strictly in `WeddingCull_manifest.json` and never overwrite subjective star ratings.
   * Capture One compatible English color tags (`Green`, `Yellow`, `Red`).
   * RAW+JPEG pairs with matching basenames share a single XMP sidecar.

4. **100% Clean-Room Native Swift Implementation**:
   * No Python runtime dependencies.
   * No AGPL/GPL contamination.
   * Native Apple Vision, Core ML, ImageIO, Accelerate, and SwiftUI.
