import Foundation
import CoreGraphics
import Vision

public struct FaceObservationResult: Sendable {
    public let boundingBox: CGRect
    public let landmarksConfidence: Float
    public let eyeOpennessConfidence: Double
    public let qualityScore: Double
    public let faceSharpness: Double
}

public struct FaceAnalysisSummary: Sendable {
    public let faceCount: Int
    public let faces: [FaceObservationResult]
    public let averageEyeOpenness: Double?
    public let rawFaceSharpness: Double?
    public let faceQualityScore: Double
}

public final class FaceAnalyzer: Sendable {
    private let qualityAnalyzer = TechnicalQualityAnalyzer()

    public init() {}

    public func analyzeFaces(in cgImage: CGImage) -> FaceAnalysisSummary {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var detectedFaces: [FaceObservationResult] = []

        let landmarksRequest = VNDetectFaceLandmarksRequest()

        do {
            try requestHandler.perform([landmarksRequest])
        } catch {
            return FaceAnalysisSummary(
                faceCount: 0,
                faces: [],
                averageEyeOpenness: nil,
                rawFaceSharpness: nil,
                faceQualityScore: 0.5
            )
        }

        guard let results = landmarksRequest.results, !results.isEmpty else {
            return FaceAnalysisSummary(
                faceCount: 0,
                faces: [],
                averageEyeOpenness: nil,
                rawFaceSharpness: nil,
                faceQualityScore: 0.5
            )
        }

        var totalEyeOpenness: Double = 0.0
        var totalFaceSharpness: Double = 0.0
        var totalQuality: Double = 0.0

        for face in results {
            let bbox = face.boundingBox
            let sharpness = qualityAnalyzer.computeRegionSharpness(cgImage: cgImage, normalizedRect: bbox)

            var eyeOpenness = 0.8 // default when landmarks aren't detailed
            if let landmarks = face.landmarks {
                let leftOpenness = estimateEyeOpenness(landmarks.leftEye)
                let rightOpenness = estimateEyeOpenness(landmarks.rightEye)
                if let l = leftOpenness, let r = rightOpenness {
                    eyeOpenness = (l + r) / 2.0
                } else if let l = leftOpenness {
                    eyeOpenness = l
                } else if let r = rightOpenness {
                    eyeOpenness = r
                }
            }

            // Size factor: larger faces in frame matter more for quality
            let faceArea = Double(bbox.width * bbox.height)
            let sizeFactor = min(1.0, faceArea * 15.0)

            // Combined face quality
            let quality = (eyeOpenness * 0.4) + (min(1.0, sharpness / 200.0) * 0.4) + (sizeFactor * 0.2)

            totalEyeOpenness += eyeOpenness
            totalFaceSharpness += sharpness
            totalQuality += quality

            detectedFaces.append(FaceObservationResult(
                boundingBox: bbox,
                landmarksConfidence: face.confidence,
                eyeOpennessConfidence: eyeOpenness,
                qualityScore: quality,
                faceSharpness: sharpness
            ))
        }

        let count = detectedFaces.count
        let avgEye = totalEyeOpenness / Double(count)
        let avgSharpness = totalFaceSharpness / Double(count)
        let avgQuality = max(0.1, min(1.0, totalQuality / Double(count)))

        return FaceAnalysisSummary(
            faceCount: count,
            faces: detectedFaces,
            averageEyeOpenness: avgEye,
            rawFaceSharpness: avgSharpness,
            faceQualityScore: avgQuality
        )
    }

    private func estimateEyeOpenness(_ eye: VNFaceLandmarkRegion2D?) -> Double? {
        guard let eye = eye, eye.pointCount >= 6 else { return nil }
        // Approximate vertical / horizontal ratio
        // Standard points: 0=outer corner, 3=inner corner, 1,2=upper lid, 4,5=lower lid
        let pts = eye.normalizedPoints
        let width = hypot(pts[0].x - pts[3].x, pts[0].y - pts[3].y)
        guard width > 0.001 else { return nil }

        let height1 = hypot(pts[1].x - pts[5].x, pts[1].y - pts[5].y)
        let height2 = hypot(pts[2].x - pts[4].x, pts[2].y - pts[4].y)
        let avgHeight = (height1 + height2) / 2.0

        let ratio = avgHeight / width
        // In natural faces, ratio ~ 0.25 to 0.4 is open, < 0.18 is squinting or closed
        let normalized = min(1.0, max(0.0, (ratio - 0.10) / 0.25))
        return Double(normalized)
    }
}
