import Foundation
import CoreGraphics
import ImageIO

public final class SyntheticWeddingGenerator: Sendable {
    public init() {}

    public struct GeneratorConfig: Sendable {
        public let baseDate: Date
        public let generateLargeImages: Bool
        public let targetTotalPhotos: Int
        public let seed: UInt64
        public var totalTargetCount: Int { targetTotalPhotos }

        public init(
            baseDate: Date = Date(timeIntervalSince1970: 1720000000), // fixed deterministic date
            generateLargeImages: Bool = true,
            targetTotalPhotos: Int = 150,
            seed: UInt64 = 42,
            totalTargetCount: Int? = nil
        ) {
            self.baseDate = baseDate
            self.generateLargeImages = generateLargeImages
            self.targetTotalPhotos = totalTargetCount ?? targetTotalPhotos
            self.seed = seed
        }
    }

    private struct DeterministicRNG {
        private var state: UInt64
        init(seed: UInt64) {
            self.state = seed != 0 ? seed : 1
        }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func randomDouble(in range: ClosedRange<Double>) -> Double {
            let n = Double(next() >> 11) / Double(1 << 53)
            return range.lowerBound + n * (range.upperBound - range.lowerBound)
        }
    }

    public func generateDataset(at destinationFolder: URL, config: GeneratorConfig = GeneratorConfig()) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        var rng = DeterministicRNG(seed: config.seed)
        var createdFiles: [URL] = []
        var currentTime = config.baseDate

        let scale = max(0.08, Double(config.targetTotalPhotos) / 150.0)
        let isSmallDataset = config.targetTotalPhotos <= 30

        let baseScenes: [(category: String, colorRGB: (CGFloat, CGFloat, CGFloat), baseCount: Int, hasFaces: Bool)] = [
            ("BridePrep", (0.95, 0.85, 0.90), 12, true),
            ("GroomPrep", (0.85, 0.85, 0.95), 10, true),
            ("Ceremony", (0.95, 0.95, 0.85), 25, true),
            ("Couple", (0.90, 0.80, 0.85), 20, true),
            ("FamilyGroups", (0.85, 0.92, 0.92), 15, true),
            ("Reception", (0.92, 0.88, 0.80), 15, true),
            ("Cake", (0.95, 0.90, 0.80), 10, true),
            ("Dance", (0.80, 0.80, 0.90), 15, true),
            ("Details", (0.92, 0.92, 0.92), 12, false)
        ]

        var photoIndex = 1

        for scene in baseScenes {
            // Gap of 25 minutes between major scenes to test temporal segmentation
            currentTime = currentTime.addingTimeInterval(1500)
            let sceneCount = max(1, Int(round(Double(scene.baseCount) * scale)))

            for i in 0..<sceneCount {
                currentTime = currentTime.addingTimeInterval(rng.randomDouble(in: 4...25))
                let filename = String(format: "IMG_%04d.jpg", photoIndex)
                let fileURL = destinationFolder.appendingPathComponent(filename)

                // Systematic quality variations: blur, dark, overexposed, normal
                let isBlurred = (i % 12 == 2)
                let isDark = (i % 15 == 4)
                let isOverexposed = (i % 18 == 6)

                let cgImage = renderSyntheticImage(
                    width: 800,
                    height: 600,
                    text: "\(scene.category) #\(i + 1)",
                    baseColor: scene.colorRGB,
                    hasFaces: scene.hasFaces,
                    isBlurred: isBlurred,
                    isDark: isDark,
                    isOverexposed: isOverexposed
                )

                try saveImage(cgImage, to: fileURL, captureDate: currentTime)
                createdFiles.append(fileURL)
                photoIndex += 1
            }

            // Burst sequences for Ceremony, Cake, and Dance
            let shouldGenerateBurst = isSmallDataset ? (scene.category == "Ceremony") : (scene.category == "Ceremony" || scene.category == "Cake" || (scale > 2.0 && scene.category == "Dance"))
            if shouldGenerateBurst {
                let burstCount = scale > 2.0 ? 2 : 1
                for burstIdx in 0..<burstCount {
                    let burstUUID = String(format: "%08X-%04X-4000-8000-%012X", UInt32(burstIdx), UInt16(rng.next() & 0xFFFF), rng.next() & 0xFFFFFFFFFFFF)
                    let burstLength = isSmallDataset ? 3 : 5
                    let burstWinnerOffset = isSmallDataset ? 1 : 2

                    for b in 0..<burstLength {
                        currentTime = currentTime.addingTimeInterval(0.3) // 300ms apart
                        let bFilename = String(format: "IMG_%04d.jpg", photoIndex)
                        let bURL = destinationFolder.appendingPathComponent(bFilename)

                        // Winner frame is sharper than other burst frames
                        let isWinner = (b == burstWinnerOffset)
                        let cgImage = renderSyntheticImage(
                            width: 800,
                            height: 600,
                            text: "\(scene.category) Burst \(burstIdx + 1) #\(b + 1)",
                            baseColor: scene.colorRGB,
                            hasFaces: scene.hasFaces,
                            isBlurred: !isWinner,
                            isDark: false,
                            isOverexposed: false
                        )

                        try saveImage(cgImage, to: bURL, captureDate: currentTime, burstUUID: burstUUID)
                        createdFiles.append(bURL)
                        photoIndex += 1
                    }
                }
            }
        }

        // Add exact duplicate
        if let firstFile = createdFiles.first {
            let dupURL = destinationFolder.appendingPathComponent("IMG_EXACT_DUP.jpg")
            try fileManager.copyItem(at: firstFile, to: dupURL)
            createdFiles.append(dupURL)
        }

        // Add RAW + JPEG pair test fixture
        // Explicitly labeled as synthetic JPEG test fixture with .CR3 extension for metadata pairing tests only
        let pairBaseName = "IMG_9990_SYNTHETIC_PAIR"
        let pairJpegURL = destinationFolder.appendingPathComponent("\(pairBaseName).JPG")
        let pairRawURL = destinationFolder.appendingPathComponent("\(pairBaseName).CR3")

        let pairImage = renderSyntheticImage(width: 800, height: 600, text: "RAW+JPEG Synthetic Fixture", baseColor: (0.9, 0.9, 0.9), hasFaces: true, isBlurred: false, isDark: false, isOverexposed: false)
        try saveImage(pairImage, to: pairJpegURL, captureDate: currentTime)
        try saveImage(pairImage, to: pairRawURL, captureDate: currentTime)
        createdFiles.append(pairJpegURL)
        createdFiles.append(pairRawURL)

        // Add corrupt image fixture
        let corruptURL = destinationFolder.appendingPathComponent("CORRUPT_IMAGE.jpg")
        let garbageData = "GARBAGE_NOT_A_VALID_JPEG_DATA_1234567890".data(using: .utf8)!
        try garbageData.write(to: corruptURL)
        createdFiles.append(corruptURL)

        // Add high-resolution image fixture if requested
        if config.generateLargeImages {
            let largeURL = destinationFolder.appendingPathComponent("IMG_LARGE_6000x4000.jpg")
            let largeCG = renderSyntheticImage(width: 4000, height: 3000, text: "HIGH RES", baseColor: (0.8, 0.85, 0.95), hasFaces: true, isBlurred: false, isDark: false, isOverexposed: false)
            try saveImage(largeCG, to: largeURL, captureDate: currentTime)
            createdFiles.append(largeURL)
        }

        // If targetTotalPhotos requires extra padding to match exact requested count:
        while createdFiles.count < config.targetTotalPhotos {
            currentTime = currentTime.addingTimeInterval(10)
            let padFilename = String(format: "IMG_%04d.jpg", photoIndex)
            let padURL = destinationFolder.appendingPathComponent(padFilename)
            let cg = renderSyntheticImage(width: 800, height: 600, text: "Photo #\(photoIndex)", baseColor: (0.88, 0.88, 0.88), hasFaces: true, isBlurred: false, isDark: false, isOverexposed: false)
            try saveImage(cg, to: padURL, captureDate: currentTime)
            createdFiles.append(padURL)
            photoIndex += 1
        }

        // Strictly guarantee targetTotalPhotos count
        if createdFiles.count > config.targetTotalPhotos {
            let excess = createdFiles.suffix(createdFiles.count - config.targetTotalPhotos)
            for file in excess {
                try? fileManager.removeItem(at: file)
            }
            createdFiles = Array(createdFiles.prefix(config.targetTotalPhotos))
        }

        return createdFiles
    }

    private func renderSyntheticImage(
        width: Int,
        height: Int,
        text: String,
        baseColor: (CGFloat, CGFloat, CGFloat),
        hasFaces: Bool,
        isBlurred: Bool,
        isDark: Bool,
        isOverexposed: Bool
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Could not create CGContext")
        }

        var r = baseColor.0
        var g = baseColor.1
        var b = baseColor.2

        if isDark {
            r *= 0.12
            g *= 0.12
            b *= 0.12
        } else if isOverexposed {
            r = min(1.0, r * 1.6 + 0.3)
            g = min(1.0, g * 1.6 + 0.3)
            b = min(1.0, b * 1.6 + 0.3)
        }

        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if !isBlurred {
            ctx.setStrokeColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            ctx.setLineWidth(CGFloat(width) / 100.0)

            for x in stride(from: 0, to: width, by: max(10, width / 8)) {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: height))
            }
            ctx.strokePath()
        }

        if hasFaces {
            let faceW = CGFloat(width) / 5.0
            let faceH = CGFloat(height) / 3.5
            let centerX = CGFloat(width) / 2.0
            let centerY = CGFloat(height) / 2.0

            ctx.setFillColor(red: 0.95, green: 0.80, blue: 0.70, alpha: 1.0)
            ctx.fillEllipse(in: CGRect(x: centerX - faceW/2, y: centerY - faceH/2, width: faceW, height: faceH))

            ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            let eyeW = faceW / 6.0
            let eyeH = isBlurred ? eyeW / 3.0 : eyeW / 1.5
            ctx.fillEllipse(in: CGRect(x: centerX - faceW/4 - eyeW/2, y: centerY + faceH/6, width: eyeW, height: eyeH))
            ctx.fillEllipse(in: CGRect(x: centerX + faceW/4 - eyeW/2, y: centerY + faceH/6, width: eyeW, height: eyeH))
        }

        return ctx.makeImage()!
    }

    private func saveImage(_ cgImage: CGImage, to fileURL: URL, captureDate: Date, burstUUID: String? = nil) throws {
        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "SyntheticWeddingGenerator", code: 1, userInfo: nil)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: captureDate)

        let exifDict: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: dateString,
            kCGImagePropertyExifExposureTime: 0.005,
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifISOSpeedRatings: [400],
            kCGImagePropertyExifFocalLength: 50.0,
            kCGImagePropertyExifLensModel: "50mm ƒ/1.4"
        ]

        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "WeddingCamera",
            kCGImagePropertyTIFFModel: "CullPro 1",
            kCGImagePropertyTIFFDateTime: dateString
        ]

        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exifDict,
            kCGImagePropertyTIFFDictionary: tiffDict,
            kCGImageDestinationLossyCompressionQuality: 0.85
        ]

        if let bUUID = burstUUID {
            properties["{MakerApple}" as CFString] = [
                "11" as CFString: bUUID
            ]
        }

        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
