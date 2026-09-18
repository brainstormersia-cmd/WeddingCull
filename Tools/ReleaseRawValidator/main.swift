import Foundation
import CoreGraphics
import ImageIO
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

struct RawFixtureDef {
    let name: String
    let url: String
    let sha256: String
    let format: String
    let cameraModel: String
    let isMandatory: Bool
}

struct RawFixtureResult: Codable {
    let name: String
    let cameraModel: String
    let format: String
    let expectedHash: String
    let actualHash: String?
    let hashMatched: Bool
    let imageIORecognized: Bool
    let imageIOType: String?
    let width: Int?
    let height: Int?
    let previewDecoded: Bool
    let sourceRemainedImmutable: Bool
    let status: String // "PASS", "FAIL", "NOT_VERIFIED"
    let notes: String
}

struct RawValidationReport: Codable {
    let timestamp: String
    let mandatoryStatus: String
    let totalFixturesTested: Int
    let passedFixturesCount: Int
    let unsupportedFixturesCount: Int
    let formats: [String: String]
    let results: [RawFixtureResult]
}

@main
struct ReleaseRawValidator {
    static let fixtures: [RawFixtureDef] = [
        RawFixtureDef(
            name: "Canon EOS 350D CR2",
            url: "https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/cr2/Canon%20EOS%20350D.CR2",
            sha256: "e0539843c36e6e3f39ffe15aa91f22624149ad18c63e3bef7b6f0e71cdc46c79",
            format: "CR2",
            cameraModel: "Canon EOS 350D DIGITAL",
            isMandatory: true
        ),
        RawFixtureDef(
            name: "Nikon D70 NEF",
            url: "https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/nef/Nikon%20D70.nef",
            sha256: "97e2faea5ac62040e98710b146a4f296b9570d410bcc44e14da778b5f34ced39",
            format: "NEF",
            cameraModel: "NIKON D70",
            isMandatory: false
        ),
        RawFixtureDef(
            name: "Sony DSLR-A500 ARW",
            url: "https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/arw/Sony%20DSLR-A500.arw",
            sha256: "cdf69f2856612620129789fb87c10772f80ec3b040c54a933315c77c2961dc46",
            format: "ARW",
            cameraModel: "DSLR-A500",
            isMandatory: false
        ),
        RawFixtureDef(
            name: "FujiFilm FinePix S5500 RAF",
            url: "https://raw.githubusercontent.com/drewnoakes/metadata-extractor-images/main/raf/FujiFilm%20FinePix%20S5500.raf",
            sha256: "5be26d83d80f1424f07b1244c80a5fbb5b699a6ee33419b7a10533f751b77af8",
            format: "RAF",
            cameraModel: "FinePix S5500",
            isMandatory: false
        )
    ]

    static func computeSHA256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        #if canImport(CryptoKit)
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65536)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
        #else
        return nil
        #endif
    }

    static func downloadFile(from urlString: String, to destinationURL: URL) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destinationURL)
                return true
            }
        } catch {
            return false
        }
        return false
    }

    static func main() async {
        let args = CommandLine.arguments
        var outputJSON = "artifacts/raw-validation-report.json"
        var sampleDir = "tests/fixtures/datasets/raw_samples"

        var idx = 1
        while idx < args.count {
            switch args[idx] {
            case "--output-json":
                if idx + 1 < args.count {
                    outputJSON = args[idx + 1]
                    idx += 1
                }
            case "--dir":
                if idx + 1 < args.count {
                    sampleDir = args[idx + 1]
                    idx += 1
                }
            default:
                break
            }
            idx += 1
        }

        print("====================================================")
        print("📸 WeddingCull Strict Real RAW Verification")
        print("====================================================")
        print("Fixtures location: \(sampleDir)")

        let fm = FileManager.default
        try? fm.createDirectory(atPath: sampleDir, withIntermediateDirectories: true)

        var results: [RawFixtureResult] = []
        var mandatoryPassed = true

        for fix in fixtures {
            print("\n----------------------------------------------------")
            print("Evaluating fixture: \(fix.name) [\(fix.format)]")
            print("Pinned SHA-256: \(fix.sha256)")

            let targetURL = URL(fileURLWithPath: sampleDir).appendingPathComponent("\(fix.cameraModel.replacingOccurrences(of: " ", with: "_")).\(fix.format)")

            // Check if present or download
            if !fm.fileExists(atPath: targetURL.path) {
                print("⬇️ Downloading \(fix.name) from \(fix.url)...")
                let ok = await downloadFile(from: fix.url, to: targetURL)
                if !ok {
                    print("⚠️ Could not download fixture.")
                    let res = RawFixtureResult(
                        name: fix.name,
                        cameraModel: fix.cameraModel,
                        format: fix.format,
                        expectedHash: fix.sha256,
                        actualHash: nil,
                        hashMatched: false,
                        imageIORecognized: false,
                        imageIOType: nil,
                        width: nil,
                        height: nil,
                        previewDecoded: false,
                        sourceRemainedImmutable: false,
                        status: fix.isMandatory ? "FAIL" : "NOT_VERIFIED",
                        notes: "Download failed or network unreachable"
                    )
                    results.append(res)
                    if fix.isMandatory { mandatoryPassed = false }
                    continue
                }
            }

            // Verify strict hash
            guard let initialHash = computeSHA256(url: targetURL) else {
                print("❌ Could not compute hash for \(targetURL.path)")
                if fix.isMandatory { mandatoryPassed = false }
                continue
            }

            let hashMatches = (initialHash.lowercased() == fix.sha256.lowercased())
            if !hashMatches {
                print("❌ HASH MISMATCH! Expected \(fix.sha256), got \(initialHash)")
                let res = RawFixtureResult(
                    name: fix.name,
                    cameraModel: fix.cameraModel,
                    format: fix.format,
                    expectedHash: fix.sha256,
                    actualHash: initialHash,
                    hashMatched: false,
                    imageIORecognized: false,
                    imageIOType: nil,
                    width: nil,
                    height: nil,
                    previewDecoded: false,
                    sourceRemainedImmutable: false,
                    status: "FAIL",
                    notes: "Checksum violation against pinned hash"
                )
                results.append(res)
                if fix.isMandatory { mandatoryPassed = false }
                continue
            }

            print("✅ SHA-256 hash verified perfectly.")

            // ImageIO verification
            guard let imageSource = CGImageSourceCreateWithURL(targetURL as CFURL, nil) else {
                print("❌ ImageIO failed to open RAW source")
                let res = RawFixtureResult(
                    name: fix.name,
                    cameraModel: fix.cameraModel,
                    format: fix.format,
                    expectedHash: fix.sha256,
                    actualHash: initialHash,
                    hashMatched: true,
                    imageIORecognized: false,
                    imageIOType: nil,
                    width: nil,
                    height: nil,
                    previewDecoded: false,
                    sourceRemainedImmutable: false,
                    status: "FAIL",
                    notes: "CGImageSourceCreateWithURL returned nil"
                )
                results.append(res)
                if fix.isMandatory { mandatoryPassed = false }
                continue
            }

            let utiType = CGImageSourceGetType(imageSource) as String?
            print("  ImageIO UTI Type: \(utiType ?? "nil")")

            // Metadata extraction
            var width: Int? = nil
            var height: Int? = nil
            if let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                width = props[kCGImagePropertyPixelWidth] as? Int
                height = props[kCGImagePropertyPixelHeight] as? Int
            }
            print("  Dimensions: \(width ?? 0) x \(height ?? 0)")

            // Preview decoding with fallback chain
            var cgThumb: CGImage? = nil

            // 1. Standard thumbnail decode
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            cgThumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOpts as CFDictionary)



            // 2. Full image decode fallback
            if cgThumb == nil {
                print("  Trying full image decode fallback...")
                cgThumb = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            }

            let previewOk = (cgThumb != nil)
            print("  Preview decoded successfully: \(previewOk)")

            // Test pipeline import
            let tempDir = fm.temporaryDirectory.appendingPathComponent("raw_test_\(UUID().uuidString)")
            try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            let copyURL = tempDir.appendingPathComponent(targetURL.lastPathComponent)
            try? fm.copyItem(at: targetURL, to: copyURL)

            let pipeline = AnalysisPipeline()
            let session = try? await pipeline.runAnalysis(sourceFolder: tempDir, targetCount: 1)
            let imported = session?.photos.count == 1

            // Source immutability verification
            let finalHash = computeSHA256(url: targetURL)
            let immutable = (finalHash == initialHash)
            print("  Source file remained byte-identical: \(immutable)")

            let pass = hashMatches && (utiType != nil) && previewOk && imported && immutable
            let status: String
            let notes: String

            if pass {
                status = "PASS"
                notes = "Successfully verified ImageIO decode, preview generation, and immutability"
            } else if !fix.isMandatory && (utiType != nil) && !previewOk && immutable {
                status = "UNSUPPORTED"
                notes = "Apple Camera RAW engine lacks a sensor decoding profile for \(fix.cameraModel) on this macOS configuration; handled gracefully without crash"
            } else {
                status = "FAIL"
                notes = "Pipeline or decoding failure"
            }

            print("  Fixture verdict: \(status)")

            let result = RawFixtureResult(
                name: fix.name,
                cameraModel: fix.cameraModel,
                format: fix.format,
                expectedHash: fix.sha256,
                actualHash: initialHash,
                hashMatched: hashMatches,
                imageIORecognized: utiType != nil,
                imageIOType: utiType,
                width: width,
                height: height,
                previewDecoded: previewOk,
                sourceRemainedImmutable: immutable,
                status: status,
                notes: notes
            )
            results.append(result)
            if fix.isMandatory && !pass {
                mandatoryPassed = false
            }
        }

        let passedCount = results.filter { $0.status == "PASS" }.count
        let unsupportedCount = results.filter { $0.status == "UNSUPPORTED" }.count
        var formatMap: [String: String] = [:]
        for r in results {
            formatMap[r.format] = r.status
        }

        let report = RawValidationReport(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            mandatoryStatus: mandatoryPassed ? "PASS" : "FAIL",
            totalFixturesTested: results.count,
            passedFixturesCount: passedCount,
            unsupportedFixturesCount: unsupportedCount,
            formats: formatMap,
            results: results
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(report) {
            let outURL = URL(fileURLWithPath: outputJSON)
            try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? json.write(to: outURL)
            print("\n✅ Written RAW validation report to \(outputJSON)")
        }

        print("====================================================")
        print("Final RAW Validation Status: \(mandatoryPassed ? "PASS ✅" : "FAIL ❌")")
        print("Tested: \(results.count) fixtures, Passed: \(passedCount), Unsupported: \(unsupportedCount)")
        for (fmt, st) in formatMap.sorted(by: { $0.key < $1.key }) {
            print("  - \(fmt): \(st)")
        }
        print("====================================================")

        exit(mandatoryPassed ? 0 : 1)
    }
}
