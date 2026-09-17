# WeddingCull 👰💍📷

**Version 1.0.0** — Fast, 100% local, intelligent wedding photo culling for macOS.

WeddingCull automatically organizes large wedding photo shoots (1,000–3,000 high-resolution photographs), groups bursts and near-duplicates, evaluates photographic quality, and proposes a balanced, diversity-aware selection (e.g. 1,500 photos → ~700 selected).

**Absolute Guarantee**: WeddingCull **never** modifies, renames, rotates, rewrites, or deletes original photographs. All processing happens entirely on your Mac without external servers or internet connection.

---

## 💻 Guide for Windows Developers & Owners

As a project owner developing on Windows, you don't need a Mac or Xcode to build, test, and release WeddingCull. The entire automated build, test, verification, and packaging pipeline executes on GitHub-hosted macOS runners.

### Step-by-Step Instructions:

1. **Open the Repository on GitHub**:
   Navigate to the repository page on GitHub (`brainstormersia-cmd/WeddingCull`).

2. **Go to GitHub Actions**:
   Click the **Actions** tab at the top of the repository.

3. **Run or Inspect CI / Release Workflows**:
   - The **CI** workflow runs automatically on every push and pull request.
   - It executes on **both** Apple Silicon (`arm64`, macOS 14) and Intel (`x86_64`, macOS 13) runners.
   - It performs unit tests, integration tests, source immutability verification, and builds the Universal binary.
   - You can also manually trigger the **CI** or **Release** workflow using the **"Run workflow"** button.

4. **Inspect PASS / FAIL Status**:
   - In the Actions tab, select the latest workflow run.
   - You can see green checkmarks for `Test (macos-14 / Apple Silicon)`, `Test (macos-13 / Intel)`, and `Universal Build & Verification`.

5. **Download the WeddingCull App**:
   - Scroll down to the **Artifacts** section at the bottom of the workflow run summary.
   - Download `WeddingCull-1.0.0-universal.zip` (or `.dmg` if available).
   - This archive contains `WeddingCull.app` with native support for both Apple Silicon and Intel Macs.

6. **Download UI Screenshots & Test Results**:
   - Download `WeddingCull-Test-Artifacts` from the Artifacts section.
   - Unzip to view high-resolution screenshots of every screen (Start, Analysis, Grid, Inspector, Burst Comparison, Export).

7. **Read the Verification and Benchmark Reports**:
   - Download `WeddingCull-Reports` to view `verification-report.json` and `benchmark.json`.

8. **Install and Run on macOS**:
   - Transfer `WeddingCull-1.0.0-universal.zip` to a Mac.
   - Double-click to unzip `WeddingCull.app`.
   - Drag `WeddingCull.app` into `/Applications`.
   - Double-click to launch!

---

## ⚡ Keyboard Workflow & Shortcuts

WeddingCull is designed for rapid keyboard-driven photographer culling:

| Key | Action |
| :--- | :--- |
| `1` | **Select photo** (`userSelected` — overrides algorithmic ranking) |
| `2` | **Mark as Alternative** |
| `3` | **Reject photo** (`userRejected` — overrides algorithmic ranking) |
| `←` / `→` | **Navigate** to previous / next photo in grid |
| `Space` | **Quick Look** / large preview |
| `Enter` | **Open Burst Comparison** (when photo belongs to a burst) |

---

## 🧑‍🤝‍🧑 Face Grouping & Model Scope

* **Face Grouping (Geometric Landmark Baseline)**:
  Uses native Apple Vision `VNFaceLandmarks2D` to extract 64-dimensional biometric proportion descriptors. Designed for coarse subject grouping within a wedding shoot (distinguishing bride, groom, wedding party members, children).
* **Limitations**:
  Geometric descriptors are not learned deep face embeddings (e.g. ArcFace). They do not guarantee identity tracking across radical expression shifts, glasses on/off, or extreme profile angles.
* **Optional Learned Model**:
  Supports optional Core ML `MobileFaceNet.mlmodelc` if installed locally.
* **Scene Classification**:
  Combines Apple Vision scene classification with optional Core ML MobileCLIP-S0 zero-shot inference (512-d normalized concept embeddings).

---

## 🔒 Privacy & Local Processing

- **Zero Cloud**: 100% of processing happens locally on device.
- **No Telemetry**: No tracking, analytics, or external API calls.
- **Offline**: Functions without an internet connection.

---

## 📦 Project Structure

```
WeddingCull/
├── Sources/               # Swift / SwiftUI / Vision / Core ML codebase
│   ├── WeddingCullApp/    # Main app entry point, Info.plist, entitlements
│   ├── Core/              # Models, metadata, metrics, categories, sessions
│   ├── Import/            # ImageIO photo discovery & RAW+JPEG pairing
│   ├── ImageProcessing/   # Previews, Laplacian sharpness, exposure, dHash
│   ├── Vision/            # Face detection, landmarks, eye openness, bursts
│   ├── ML/                # Scene classification & MobileCLIP zero-shot
│   ├── Clustering/        # Temporal moments & Person clustering
│   ├── Ranking/           # Robust normalization & quality scoring
│   ├── Selection/         # Diversity-aware MMR exact target selection
│   ├── Export/            # Copy originals, structure options, CSV/JSON manifest
│   ├── Persistence/       # Session serialization and cache validation
│   └── UI/                # SwiftUI views (3-area macOS layout, inspector, dialogs)
├── Tests/                 # Unit, integration, source immutability, UI tests
├── Tools/                 # Synthetic wedding dataset generator
├── scripts/               # bootstrap, test, build-release, package, verify
└── .github/workflows/     # GitHub Actions CI/CD matrix workflows
```
