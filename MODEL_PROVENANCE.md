# Model Provenance & Licensing Notice

## Built-In AI Pipeline (Primary)

* **Technology**: Apple Vision Framework (`Vision.framework`)
* **Requests**: `VNClassifyImageRequest`, `VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNGenerateImageFeaturePrintRequest`
* **Licensing**: Native macOS SDK component provided directly by Apple Inc.
* **Network Requirement**: 0 bytes (fully offline, embedded in macOS)
* **Single Point of Failure Prevention**: The core application functions 100% on Apple Vision without requiring external model downloads.

---

## Optional Advanced AI Mode (Apple Silicon)

* **Architecture**: MobileCLIP-S0 Core ML Model
* **Source**: Apple Sample Code / Apple Machine Learning Research
* **Model Revision**: S0 (Compact ViT image encoder)
* **License**: Apple Sample Code License / Non-Commercial Research
* **Offline Execution**: Core ML runs entirely on Apple Silicon Neural Engine / GPU via Metal.
* **Fallback Protocol**: If the Core ML model is absent or execution occurs on Intel hardware, WeddingCull gracefully activates the built-in Vision pipeline without degradation of primary user flow.
