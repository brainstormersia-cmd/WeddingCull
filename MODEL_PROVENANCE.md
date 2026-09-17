# Model Provenance & Licensing Notice

**Document Status**: Production Reference  
**Last Audited**: September 2026  
**Application**: WeddingCull

---

## 1. Native Apple Vision Pipeline (Built-In Baseline)

* **Framework**: Apple Vision (`Vision.framework`)
* **Core Requests**:
  * `VNClassifyImageRequest` (scene and object classification fallback)
  * `VNDetectFaceRectanglesRequest` (fast face localization and count)
  * `VNDetectFaceLandmarksRequest` (facial geometry, inter-ocular distance, eye openness ratio)
  * `VNGenerateImageFeaturePrintRequest` (perceptual feature print duplicate detection)
* **Licensing**: Native macOS SDK component provided directly by Apple Inc. as part of macOS 13+.
* **Network Requirement**: 0 bytes (100% local, offline, zero download required).
* **Robustness Guarantee**: The application is fully functional using only the native Vision pipeline even if no external neural model is ever downloaded.

---

## 2. Advanced Scene Classifier: MobileCLIP-S0

* **Architecture**: MobileCLIP-S0 (Compact Vision Transformer Image Encoder)
* **Model Source**:
  * Code: `apple/ml-mobileclip` (GitHub)
  * Core ML Weights: `apple/coreml-mobileclip` (Hugging Face Model Hub)
* **Code License**: MIT License (official Apple repository).
* **Model Weights License**: Apple Machine Learning Research Model Terms of Use (per model repository agreement).
* **Technical Specifications**:
  * Input: 256×256 pixels, RGB / BGRA CVPixelBuffer.
  * Output: 512-dimensional normalized embedding vector.
  * Text Context Length: 77 tokens.
* **Build-Time vs. Runtime Separation**:
  * The text encoder (`mobileclip_s0_text.mlpackage`) is utilized exclusively at development/build time via `scripts/generate-concept-embeddings.py` to evaluate multiple wedding scene prompts per category and produce authentic, multi-prompt averaged 512-d concept embeddings.
  * The runtime distributed application ships **only** the precomputed 512-d embeddings (`WeddingConceptsEmbeddings.json`) and optionally the image encoder (`mobileclip_s0_image.mlpackage` / `.mlmodelc`).
  * Python is **never** shipped or executed inside the distributed application.
* **Hardware Execution Profile**:
  * **Intel Macs (x86_64)**: Runs via Core ML with `.cpuAndGPU` compute units utilizing Intel Core CPUs and integrated/discrete GPUs. Does not crash and does not silently fall through.
  * **Apple Silicon Macs (arm64)**: Runs via Core ML with `.all` compute units utilizing the Apple Neural Engine (ANE) and Metal GPU.
* **Graceful Degradation**:
  * If the model file is not present on disk, `MobileCLIPClassifier` automatically activates `VisionSceneClassifier` without user intervention or workflow failure. Runtime telemetry explicitly indicates whether `.mobileCLIP` or `.visionFallback` was executed.

---

## 3. Face Grouping & Biometric Descriptors

* **Current Implementation**: `FaceIdentityRecognizer` derives 64-dimensional geometric biometric descriptors from `VNFaceLandmarks2D` (inter-ocular ratio, eye widths, nose-to-mouth proportions, chin contour distances, and facial symmetry).
* **Classification**: Face Grouping (Geometric Landmark Analysis). Suitable for coarse wedding cluster separation (e.g., distinguishing bride, groom, wedding party members).
* **Learned Embeddings Option**:
  * If a compiled `MobileFaceNet.mlmodelc` or `ArcFace.mlmodelc` is placed in `~/Library/Application Support/WeddingCull/Models/` or the app bundle, `FaceIdentityRecognizer` switches to learned 128-d face identity vectors.
  * Bundled models must strictly comply with commercial/non-commercial distribution requirements.

---

## 4. Privacy & Offline Boundary

* All models run strictly in-process on the local machine.
* No image data, face landmarks, embeddings, or metadata are ever transmitted over the network.
* No telemetry contains photographic, biometric, or personal identifier data.
