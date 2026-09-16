import Foundation
import CoreGraphics

public struct PerceptualHash: Sendable {
    /// Computes a 64-bit dHash (difference hash) from a CGImage
    public static func computeDHash(from cgImage: CGImage) -> UInt64? {
        let width = 9
        let height = 8

        var rawData = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for row in 0..<height {
            for col in 0..<8 {
                let leftPixel = rawData[row * width + col]
                let rightPixel = rawData[row * width + col + 1]
                if leftPixel > rightPixel {
                    let bitIndex = row * 8 + col
                    hash |= (1 << UInt64(bitIndex))
                }
            }
        }

        return hash
    }

    /// Computes Hamming distance between two 64-bit hashes (0 to 64)
    public static func hammingDistance(_ hashA: UInt64, _ hashB: UInt64) -> Int {
        return (hashA ^ hashB).nonzeroBitCount
    }

    /// Returns a normalized similarity score between 0.0 (completely different) and 1.0 (identical)
    public static func similarity(_ hashA: UInt64, _ hashB: UInt64) -> Double {
        let distance = hammingDistance(hashA, hashB)
        return max(0.0, 1.0 - (Double(distance) / 64.0))
    }
}
