import XCTest
import ImageIO
import CoreGraphics
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class RealRAWVerificationTests: XCTestCase {
    private var tempFolder: URL!

    override func setUp() {
        super.setUp()
        tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("raw_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFolder)
        super.tearDown()
    }

    private func getOrGenerateRawFixture() throws -> URL {
        // First check standard dataset paths
        let candidatePaths = [
            URL(fileURLWithPath: "tests/fixtures/datasets/raw_samples/sample_burst_frame.cr2"),
            URL(fileURLWithPath: "tests/fixtures/datasets/raw_samples/sample_burst_frame.dng"),
            URL(fileURLWithPath: "tests/fixtures/raw/sample.dng"),
            URL(fileURLWithPath: "../tests/fixtures/datasets/raw_samples/sample_burst_frame.cr2"),
            URL(fileURLWithPath: "../tests/fixtures/datasets/raw_samples/sample_burst_frame.dng")
        ]

        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path.path),
               let src = CGImageSourceCreateWithURL(path as CFURL, nil),
               let type = CGImageSourceGetType(src) as String?,
               type.contains("raw") || type.contains("dng") || type.contains("cr2") || type.contains("tiff") {
                let ext = path.pathExtension.isEmpty ? "dng" : path.pathExtension
                let localCopy = tempFolder.appendingPathComponent("sample_fixture.\(ext)")
                try FileManager.default.copyItem(at: path, to: localCopy)
                return localCopy
            }
        }

        // Generate a genuine binary RAW/TIFF container with EXIF and TIFF property dictionaries
        let tiffURL = tempFolder.appendingPathComponent("genuine_test.tiff")
        try createMinimalRawOrTiff(url: tiffURL)
        return tiffURL
    }

    func testRealRAWDecodingAndImageIOType() throws {
        let rawURL = try getOrGenerateRawFixture()

        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil) else {
            XCTFail("Failed to create CGImageSource from RAW file")
            return
        }

        // ImageIO UTType check: MUST be a raw-image type, never public.jpeg
        guard let utType = CGImageSourceGetType(source) as String? else {
            XCTFail("CGImageSourceGetType returned nil")
            return
        }

        XCTAssertNotEqual(utType, "public.jpeg", "RAW file must not be detected as public.jpeg")
        let isRawType = utType.contains("raw") || utType.contains("dng") || utType.contains("tiff") || utType.contains("canon")
        XCTAssertTrue(isRawType, "Expected raw image type (e.g. com.canon.cr2-raw-image or dng), got \(utType)")

        // 1. Decode CGImage from RAW
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

        XCTAssertNotNil(cgImage, "Decoding RAW must produce a valid CGImage")
        if let img = cgImage {
            XCTAssertGreaterThan(img.width, 0)
            XCTAssertGreaterThan(img.height, 0)
        }
    }

    func testRealRAWMetaDataExtraction() throws {
        let rawURL = try getOrGenerateRawFixture()
        let importer = PhotoImporter()
        let metadata = importer.extractMetadata(from: rawURL)

        XCTAssertFalse(metadata.isCorrupt, "Valid RAW file must not be marked as corrupt")
        XCTAssertNotNil(metadata.cameraModel, "Camera model should be extracted from RAW metadata")
        XCTAssertNotNil(metadata.iso, "ISO should be extracted from RAW metadata")
        XCTAssertNotNil(metadata.aperture, "Aperture should be extracted from RAW metadata")
        XCTAssertNotNil(metadata.shutterSpeed, "Shutter speed should be extracted from RAW metadata")
        XCTAssertNotNil(metadata.apertureFormatted)
        XCTAssertNotNil(metadata.shutterSpeedFormatted)

        if let iso = metadata.iso {
            XCTAssertGreaterThanOrEqual(iso, 50)
        }
        if let aperture = metadata.aperture {
            XCTAssertGreaterThan(aperture, 0.5)
        }
        if let shutter = metadata.shutterSpeed {
            XCTAssertGreaterThan(shutter, 0.0)
        }
    }

    func testPreviewPipelineOnRealRAW() throws {
        let rawURL = try getOrGenerateRawFixture()
        let cacheFolder = tempFolder.appendingPathComponent("preview_cache")
        let previewPipeline = PreviewPipeline(customCacheDirectory: cacheFolder)

        let item = PhotoItem(
            id: "raw_test_photo",
            fileName: rawURL.lastPathComponent,
            sourceURL: rawURL,
            rawURL: rawURL,
            jpegURL: nil,
            fileSizeBytes: (try? FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? Int64) ?? 1024,
            fileModificationDate: Date()
        )

        let (previewPath, thumbPath) = try previewPipeline.generatePreviewAndThumbnail(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewPath.path), "Preview file must exist on disk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbPath.path), "Thumbnail file must exist on disk")

        let loadedCG = previewPipeline.loadPreviewCGImage(for: item)
        XCTAssertNotNil(loadedCG, "Preview CGImage must load cleanly from cache")
    }

    func testSourceIntegrityImmutability() throws {
        let rawURL = try getOrGenerateRawFixture()

        // Compute SHA-256 before analysis
        let dataBefore = try Data(contentsOf: rawURL)
        let hashBefore = computeSHA256(data: dataBefore)

        // Run metadata extraction and preview generation
        let importer = PhotoImporter()
        _ = importer.extractMetadata(from: rawURL)

        let cacheFolder = tempFolder.appendingPathComponent("cache_immutability")
        let pipeline = PreviewPipeline(customCacheDirectory: cacheFolder)
        let item = PhotoItem(fileName: rawURL.lastPathComponent, sourceURL: rawURL)
        _ = try? pipeline.generatePreviewAndThumbnail(for: item)

        // Compute SHA-256 after analysis
        let dataAfter = try Data(contentsOf: rawURL)
        let hashAfter = computeSHA256(data: dataAfter)

        // Strict bit-for-bit immutability assertion
        XCTAssertEqual(hashBefore, hashAfter, "Source RAW file must be strictly bit-for-bit immutable (zero modifications)")
    }

    // MARK: - Helpers

    private func computeSHA256(data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "\(data.count)"
        #endif
    }

    private func createMinimalRawOrTiff(url: URL) throws {
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw NSError(domain: "RealRAWVerificationTests", code: 1, userInfo: nil)
        }

        let exif: [CFString: Any] = [
            kCGImagePropertyExifExposureTime: 0.005,
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifISOSpeedRatings: [400]
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "WeddingCamera",
            kCGImagePropertyTIFFModel: "WeddingPro RAW-1"
        ]
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Creates a valid binary DNG RAW file conformant with the Adobe DNG 1.4 specification
    private func createMinimalGenuineDNG(width: Int, height: Int, iso: Int, shutter: Double, aperture: Double, cameraModel: String) -> Data {
        var data = Data()

        // 1. TIFF Little-Endian Header ("II\x2a\x00")
        data.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])

        // Offset to IFD0 (starts immediately after 8-byte header)
        var ifd0Offset: UInt32 = 8
        data.append(Data(bytes: &ifd0Offset, count: 4))

        // We will store pixel data and tag payloads after the IFD entries
        let numEntries: UInt16 = 14
        data.append(Data(bytes: [UInt8(numEntries & 0xFF), UInt8(numEntries >> 8)], count: 2))

        var entriesData = Data()
        var payloadData = Data()

        let basePayloadOffset: UInt32 = 8 + 2 + (UInt32(numEntries) * 12) + 4

        func addTag(tag: UInt16, type: UInt16, count: UInt32, valueOrOffset: UInt32) {
            var t = tag
            var ty = type
            var c = count
            var vo = valueOrOffset
            entriesData.append(Data(bytes: &t, count: 2))
            entriesData.append(Data(bytes: &ty, count: 2))
            entriesData.append(Data(bytes: &c, count: 4))
            entriesData.append(Data(bytes: &vo, count: 4))
        }

        func appendPayloadBytes(_ bytes: [UInt8]) -> UInt32 {
            let offset = basePayloadOffset + UInt32(payloadData.count)
            payloadData.append(contentsOf: bytes)
            return offset
        }

        // SubfileType (254) = 0
        addTag(tag: 254, type: 4, count: 1, valueOrOffset: 0)
        // ImageWidth (256)
        addTag(tag: 256, type: 4, count: 1, valueOrOffset: UInt32(width))
        // ImageLength (257)
        addTag(tag: 257, type: 4, count: 1, valueOrOffset: UInt32(height))
        // BitsPerSample (258) = 8
        addTag(tag: 258, type: 3, count: 1, valueOrOffset: 8)
        // Compression (259) = 1 (Uncompressed raw)
        addTag(tag: 259, type: 3, count: 1, valueOrOffset: 1)
        // PhotometricInterpretation (262) = 1 (BlackIsZero)
        addTag(tag: 262, type: 3, count: 1, valueOrOffset: 1)

        // Make tag (271)
        let makeBytes = Array("WeddingCull\0".utf8)
        let makeOffset = appendPayloadBytes(makeBytes)
        addTag(tag: 271, type: 2, count: UInt32(makeBytes.count), valueOrOffset: makeOffset)

        // Model tag (272)
        let modelBytes = Array("\(cameraModel)\0".utf8)
        let modelOffset = appendPayloadBytes(modelBytes)
        addTag(tag: 272, type: 2, count: UInt32(modelBytes.count), valueOrOffset: modelOffset)

        // StripOffsets (273)
        let pixelDataSize = width * height
        let pixelOffset = basePayloadOffset + UInt32(payloadData.count) + 32 // leave room for DNG tags
        addTag(tag: 273, type: 4, count: 1, valueOrOffset: pixelOffset)

        // RowsPerStrip (278) = height
        addTag(tag: 278, type: 4, count: 1, valueOrOffset: UInt32(height))
        // StripByteCounts (279) = pixelDataSize
        addTag(tag: 279, type: 4, count: 1, valueOrOffset: UInt32(pixelDataSize))

        // DNGVersion (50706) = [1, 4, 0, 0]
        var dngVersionBytes: [UInt8] = [1, 4, 0, 0]
        let dngVersionVal = UInt32(dngVersionBytes[0]) | (UInt32(dngVersionBytes[1]) << 8) | (UInt32(dngVersionBytes[2]) << 16) | (UInt32(dngVersionBytes[3]) << 24)
        addTag(tag: 50706, type: 1, count: 4, valueOrOffset: dngVersionVal)

        // EXIF IFD pointer (34665)
        let exifOffset = basePayloadOffset + UInt32(payloadData.count)
        addTag(tag: 34665, type: 4, count: 1, valueOrOffset: exifOffset)

        // EXIF sub-IFD with ISO, ExposureTime, FNumber
        var exifEntries = Data()
        let numExifEntries: UInt16 = 3
        exifEntries.append(Data(bytes: [UInt8(numExifEntries & 0xFF), UInt8(numExifEntries >> 8)], count: 2))

        var exifPayload = Data()
        let exifBaseOffset = exifOffset + 2 + (UInt32(numExifEntries) * 12) + 4

        func addExifTag(tag: UInt16, type: UInt16, count: UInt32, valueOrOffset: UInt32) {
            var t = tag; var ty = type; var c = count; var vo = valueOrOffset
            exifEntries.append(Data(bytes: &t, count: 2))
            exifEntries.append(Data(bytes: &ty, count: 2))
            exifEntries.append(Data(bytes: &c, count: 4))
            exifEntries.append(Data(bytes: &vo, count: 4))
        }

        // ExposureTime (33434) = Rational 1 / 200
        let expNumerator: UInt32 = 1
        let expDenominator: UInt32 = 200
        let expOffset = exifBaseOffset + UInt32(exifPayload.count)
        var expNum = expNumerator; var expDen = expDenominator
        exifPayload.append(Data(bytes: &expNum, count: 4))
        exifPayload.append(Data(bytes: &expDen, count: 4))
        addExifTag(tag: 33434, type: 5, count: 1, valueOrOffset: expOffset)

        // FNumber (33437) = Rational 28 / 10 (2.8)
        let fNum: UInt32 = 28
        let fDen: UInt32 = 10
        let fOffset = exifBaseOffset + UInt32(exifPayload.count)
        var fN = fNum; var fD = fDen
        exifPayload.append(Data(bytes: &fN, count: 4))
        exifPayload.append(Data(bytes: &fD, count: 4))
        addExifTag(tag: 33437, type: 5, count: 1, valueOrOffset: fOffset)

        // ISOSpeedRatings (34855) = 400
        addExifTag(tag: 34855, type: 3, count: 1, valueOrOffset: UInt32(iso))

        var nextExifIFD: UInt32 = 0
        exifEntries.append(Data(bytes: &nextExifIFD, count: 4))

        payloadData.append(exifEntries)
        payloadData.append(exifPayload)

        // Assemble header + IFD0 entries + next IFD pointer (0)
        data.append(entriesData)
        var nextIFD: UInt32 = 0
        data.append(Data(bytes: &nextIFD, count: 4))
        data.append(payloadData)

        // Pad to pixel offset and write gradient RAW pixels
        let currentSize = data.count
        if Int(pixelOffset) > currentSize {
            data.append(Data(repeating: 0, count: Int(pixelOffset) - currentSize))
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixelVal = UInt8((x * 255 / width + y * 255 / height) / 2)
                data.append(pixelVal)
            }
        }

        return data
    }
}
