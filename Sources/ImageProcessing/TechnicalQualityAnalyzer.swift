import Foundation
import CoreGraphics
import Accelerate

public struct TechnicalQualityResult: Sendable {
    public let rawSharpness: Double
    public let meanLuminance: Double
    public let shadowClipping: Double
    public let highlightClipping: Double
    public let dynamicRangeProxy: Double
    public let contrastProxy: Double
    public let compositionProxyScore: Double
    public let isSevereUnderexposed: Bool
    public let isSevereOverexposed: Bool
}

public final class TechnicalQualityAnalyzer: Sendable {
    public init() {}

    /// Analyzes an image for technical quality metrics (sharpness, exposure, contrast, composition)
    public func analyze(cgImage: CGImage) -> TechnicalQualityResult {
        // Downscale to ~800px on long edge for fast, reliable, memory-efficient analysis
        let targetLongEdge = 800
        let origWidth = cgImage.width
        let origHeight = cgImage.height
        let scale = min(1.0, Double(targetLongEdge) / Double(max(origWidth, origHeight)))
        let width = max(16, Int(Double(origWidth) * scale))
        let height = max(16, Int(Double(origHeight) * scale))

        var grayBuffer = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &grayBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return TechnicalQualityResult(
                rawSharpness: 0.0,
                meanLuminance: 0.5,
                shadowClipping: 0.0,
                highlightClipping: 0.0,
                dynamicRangeProxy: 0.5,
                contrastProxy: 0.5,
                compositionProxyScore: 0.5,
                isSevereUnderexposed: false,
                isSevereOverexposed: false
            )
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 1. Exposure & Contrast metrics
        var sumLuminance: Double = 0.0
        var shadowPixels = 0
        var highlightPixels = 0
        let totalPixels = Double(width * height)

        var histogram = [Int](repeating: 0, count: 256)
        for val in grayBuffer {
            histogram[Int(val)] += 1
            sumLuminance += Double(val)
            if val < 15 { shadowPixels += 1 }
            if val > 240 { highlightPixels += 1 }
        }

        let meanLuminance = (sumLuminance / totalPixels) / 255.0
        let shadowClipping = Double(shadowPixels) / totalPixels
        let highlightClipping = Double(highlightPixels) / totalPixels

        // Dynamic range proxy: 98th percentile luminance - 2nd percentile luminance
        var cumSum = 0
        var p2: Double = 0.0
        var p98: Double = 255.0
        let targetP2 = Int(totalPixels * 0.02)
        let targetP98 = Int(totalPixels * 0.98)

        for (bin, count) in histogram.enumerated() {
            cumSum += count
            if cumSum >= targetP2 && p2 == 0.0 {
                p2 = Double(bin)
            }
            if cumSum >= targetP98 && p98 == 255.0 {
                p98 = Double(bin)
                break
            }
        }
        let dynamicRangeProxy = max(0.0, min(1.0, (p98 - p2) / 255.0))

        // Contrast: standard deviation of luminance
        var varianceSum: Double = 0.0
        let meanVal = sumLuminance / totalPixels
        for val in grayBuffer {
            let diff = Double(val) - meanVal
            varianceSum += diff * diff
        }
        let stdDev = sqrt(varianceSum / totalPixels)
        let contrastProxy = max(0.0, min(1.0, stdDev / 64.0))

        let isSevereUnderexposed = meanLuminance < 0.05 && shadowClipping > 0.80
        let isSevereOverexposed = meanLuminance > 0.95 && highlightClipping > 0.80

        // 2. Sharpness via 3x3 Laplacian filter:
        // [  0,  1,  0 ]
        // [  1, -4,  1 ]
        // [  0,  1,  0 ]
        // 2. Sharpness & Composition via combined single-pass scan
        var laplacianSum: Double = 0.0
        var laplacianSqSum: Double = 0.0
        var validLaplacianCount = 0

        // Composition proxy (Rule of thirds energy distribution)
        let thirdsX1 = width / 3
        let thirdsX2 = (width * 2) / 3
        let thirdsY1 = height / 3
        let thirdsY2 = (height * 2) / 3

        var centralEnergy: Double = 0.0
        var peripheralEnergy: Double = 0.0

        for y in 1..<(height - 1) {
            let rowOffset = y * width
            let topOffset = (y - 1) * width
            let bottomOffset = (y + 1) * width
            let inYThirds = y >= thirdsY1 && y <= thirdsY2

            for x in 1..<(width - 1) {
                let center = Int(grayBuffer[rowOffset + x])
                let top = Int(grayBuffer[topOffset + x])
                let bottom = Int(grayBuffer[bottomOffset + x])
                let left = Int(grayBuffer[rowOffset + x - 1])
                let right = Int(grayBuffer[rowOffset + x + 1])

                let laplacian = top + bottom + left + right - (4 * center)
                let dLap = Double(laplacian)
                laplacianSum += dLap
                laplacianSqSum += dLap * dLap
                validLaplacianCount += 1

                let edgeVal = abs(top - bottom) + abs(left - right)
                let inXThirds = x >= thirdsX1 && x <= thirdsX2
                if inYThirds && inXThirds {
                    centralEnergy += Double(edgeVal)
                } else {
                    peripheralEnergy += Double(edgeVal)
                }
            }
        }

        let rawSharpness: Double
        if validLaplacianCount > 0 {
            let meanLap = laplacianSum / Double(validLaplacianCount)
            let lapVariance = (laplacianSqSum / Double(validLaplacianCount)) - (meanLap * meanLap)
            rawSharpness = max(0.0, lapVariance)
        } else {
            rawSharpness = 0.0
        }

        let totalEnergy = centralEnergy + peripheralEnergy
        let compositionProxyScore = totalEnergy > 0 ? max(0.2, min(1.0, (centralEnergy / totalEnergy) * 2.0)) : 0.5

        return TechnicalQualityResult(
            rawSharpness: rawSharpness,
            meanLuminance: meanLuminance,
            shadowClipping: shadowClipping,
            highlightClipping: highlightClipping,
            dynamicRangeProxy: dynamicRangeProxy,
            contrastProxy: contrastProxy,
            compositionProxyScore: compositionProxyScore,
            isSevereUnderexposed: isSevereUnderexposed,
            isSevereOverexposed: isSevereOverexposed
        )
    }

    /// Computes sharpness specifically on a cropped face region
    public func computeRegionSharpness(cgImage: CGImage, normalizedRect: CGRect) -> Double {
        let origWidth = Double(cgImage.width)
        let origHeight = Double(cgImage.height)

        // Vision coordinates are normalized with origin at bottom-left
        let cropX = max(0, Int(normalizedRect.origin.x * origWidth))
        let cropY = max(0, Int((1.0 - normalizedRect.origin.y - normalizedRect.size.height) * origHeight))
        let cropW = min(cgImage.width - cropX, max(10, Int(normalizedRect.size.width * origWidth)))
        let cropH = min(cgImage.height - cropY, max(10, Int(normalizedRect.size.height * origHeight)))

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return 0.0
        }

        let result = analyze(cgImage: cropped)
        return result.rawSharpness
    }
}
