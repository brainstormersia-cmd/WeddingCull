# WeddingCull Architecture Specification

## Overview

WeddingCull is a native macOS application engineered for high-throughput, local wedding photo culling. It is built using Swift, SwiftUI, Vision, Core ML, ImageIO, Accelerate/vImage, and AppKit.

---

## 1. Hardware Capability System

The `HardwareCapabilities` subsystem queries host architecture and resources dynamically:
- Detects CPU architecture (`arm64` vs `x86_64`) via `utsname`.
- Identifies logical CPU cores and physical RAM.
- Verifies Metal GPU acceleration availability.
- Dynamic concurrency limiter:
  - Apple Silicon: up to 8 parallel preview operations.
  - Intel: up to 4 parallel preview operations.
- Two runtime processing profiles:
  - **Basic Profile**: Default on Intel. Import, ImageIO metadata, preview generation, Laplacian sharpness, exposure analysis, Vision face detection, perceptual hashing, duplicate/burst detection, temporal segmentation, MMR diversity selection, review UI, export.
  - **Advanced Profile**: Default on Apple Silicon. Adds MobileCLIP Core ML semantic embeddings, zero-shot wedding category prompts, and enhanced person clustering.

---

## 2. Processing Pipeline

The `AnalysisPipeline` operates in structured, async/await phases:

```
[Discovery & Import]
       ↓
[Preview & Thumbnail Generation (ImageIO 1600px)]
       ↓
[Technical Quality (Laplacian Sharpness, Exposure, Contrast)]
       ↓
[Face Analysis (Vision Rectangles, Landmarks, Eye Openness)]
       ↓
[Duplicate & Burst Detection (Staged Hashing, dHash, Feature Prints)]
       ↓
[Temporal Segmentation (Timeline Moment Detection)]
       ↓
[Semantic Classification (Vision / MobileCLIP Zero-Shot)]
       ↓
[Face Grouping & Primary Couple Suggestion (Geometric Landmark Analysis)]
       ↓
[Robust Normalization & Multi-Component Scoring]
       ↓
[Diversity-Aware MMR Exact Target Selection]
```

---

## 3. Memory Safety & Preview Pipeline

Processing 3,000 photos at 45+ megapixels without crashing requires strict memory safeguards:
- **No full decoded bitmaps in RAM**: Full RAW and JPEG files are never kept in memory.
- **ImageIO Thumbnail Extraction**: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize: 1600` produces lightweight analysis previews.
- **Autoreleasepool Scopes**: Every preview is processed within an explicit `autoreleasepool`, flushing intermediate buffers immediately.
- **Disk Cache**: Previews are written to `~/Library/Caches/WeddingCull/previews/` and `thumbs/`. Decoded bitmaps are immediately dropped from RAM.

---

## 4. Technical Quality Metrics

Rather than using a single opaque score, quality is evaluated across distinct physical dimensions:
- **Sharpness**: 3x3 Laplacian filter kernel convolution variance over grayscale luminance.
- **Face-Region Sharpness**: Measured specifically over cropped bounding boxes of detected faces to ensure in-focus faces are prioritized over sharp backgrounds.
- **Exposure**: Mean luminance, shadow clipping percentage (<5%), highlight clipping percentage (>95%), and dynamic range proxy (98th - 2nd percentile).
- **Face Quality**: Vision face observation confidence, eye-aspect ratio openness approximation, face size relative to frame, and face pose.
- **Composition Proxy**: Distribution of high-contrast edge energy across the rule-of-thirds grid.

---

## 5. Face Grouping & Biometric Descriptors

- **Geometric Landmark Baseline (Native Apple Vision)**:
  By default, `FaceIdentityRecognizer` computes 64-dimensional geometric descriptors from `VNFaceLandmarks2D` (inter-ocular distance, eye widths, nose-to-mouth proportions, chin contour, and symmetry).
  - **Intended Scope**: Coarse subject grouping within a single wedding (e.g. distinguishing bride, groom, wedding party members, children).
  - **Limitations**: This is **not** learned deep face recognition (e.g. ArcFace). It will not guarantee identity persistence across radical expression changes, glasses on/off, or extreme profile angles.
  - **Learned Model Support**: If `MobileFaceNet.mlmodelc` is placed in Application Support, `FaceIdentityRecognizer` activates 128-d learned embeddings.

---

## 6. Ranking & Robust Normalization

Lighting and camera settings vary across shoots. Fixed absolute thresholds fail across different wedding styles.
- **Robust Normalization**: Uses 10th percentile and 90th percentile clamping (`RobustNormalizer`) computed across the imported collection.
- **Component Breakdown**:
  - `sharpnessScore`
  - `faceSharpnessScore`
  - `exposureScore`
  - `faceQualityScore`
  - `compositionProxyScore`
  - `semanticImportanceScore`
  - `technicalScore`
  - `overallScore`

---

## 7. Diversity-Aware Selection & Exact Target Count

Simple top-N sorting over-selects repetitive shots (e.g. 200 nearly identical bride portraits and 2 ceremony photos). WeddingCull solves this via:
- **Segment Coverage Quotas**: Proportional allocation based on moment duration, photo count, and category importance.
- **Dominance Cap**: No single temporal segment may exceed 60% of the final proposed selection.
- **Category Coverage**: Underrepresented categories receive a diversity boost in MMR to ensure balanced storytelling.
- **Maximal Marginal Relevance (MMR)**:
  $$\text{Utility}(p) = \lambda \cdot \text{Score}(p) - (1 - \lambda) \cdot \max_{s \in \text{Selected}} \text{Sim}(p, s)$$
- **Exact Target Count Guarantee**:
  If the photographer requests 700 photos:
  1. High-diversity pass selects the best candidates per segment quota.
  2. Global MMR fills remaining slots while penalizing near-duplicates and duplicate burst frames.
  3. If strict thresholds leave slots open, thresholds are progressively relaxed to hit **exactly** 700.
  4. If fewer than 700 valid photos exist in the entire shoot, selects all valid photos and reports the count transparently.
- **User Overrides Guarantee**:
  - User-selected photos (`userSelected`, key `1`) are **always** retained.
  - User-rejected photos (`userRejected`, key `3`) are **never** selected by automatic re-ranking.

---

## 7. Absolute Source Immutability

WeddingCull enforces read-only access to photographer source files:
- Never renames, moves, or rewrites source files.
- Never writes metadata or sidecars into source directories.
- Automated tests verify SHA-256 hashes of all source files before and after analysis and export. Any hash discrepancy triggers an immediate test failure.
