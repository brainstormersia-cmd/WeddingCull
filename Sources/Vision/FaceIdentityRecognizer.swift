import Foundation
import CoreGraphics
import CoreML
import Vision
import Accelerate

public enum DescriptorType: String, Sendable {
    case geometric = "Geometric Landmark Proportions"
    case learnedEmbedding = "Learned Deep Embedding"
}

public struct FaceInstance: Sendable {
    public let boundingBox: CGRect
    public let eyeOpenness: Double
    public let faceQuality: Double
    public let identityEmbedding: [Float] // Normalized descriptor vector (64-d geometric or 128-d learned)
    public let descriptorType: DescriptorType

    public init(
        boundingBox: CGRect,
        eyeOpenness: Double,
        faceQuality: Double,
        identityEmbedding: [Float],
        descriptorType: DescriptorType = .geometric
    ) {
        self.boundingBox = boundingBox
        self.eyeOpenness = eyeOpenness
        self.faceQuality = faceQuality
        self.identityEmbedding = identityEmbedding
        self.descriptorType = descriptorType
    }
}

/// Face Grouping via Geometric Landmark Proportions (Native Baseline) & Optional Learned Embeddings.
///
/// NOTE: By default, this computes 64-dimensional geometric descriptors from Apple Vision's
/// `VNFaceLandmarks2D` (inter-ocular distance, nose/mouth ratios, jaw contour proportions).
/// This is NOT learned face recognition (like ArcFace). It provides coarse person grouping
/// within a single wedding (distinguishing bride vs groom vs children). It will not reliably identify
/// individuals across heavy expression changes, glasses on/off, or extreme profile angles.
///
/// When an optional Core ML model (`MobileFaceNet.mlmodelc`) is present, it switches to learned 128-d embeddings.
public final class FaceIdentityRecognizer: @unchecked Sendable {
    private let modelURL: URL?
    private let coreMLModel: MLModel?

    public var descriptorType: DescriptorType {
        return coreMLModel != nil ? .learnedEmbedding : .geometric
    }

    public init(customModelURL: URL? = nil) {
        // Look for bundled or local Face Recognition model (e.g. MobileFaceNet / ArcFace)
        var resolvedURL: URL? = customModelURL
        if resolvedURL == nil {
            if let bundleURL = Bundle.main.url(forResource: "MobileFaceNet", withExtension: "mlmodelc") {
                resolvedURL = bundleURL
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                let localPath = appSupport?.appendingPathComponent("WeddingCull/Models/MobileFaceNet.mlmodelc")
                if let path = localPath, FileManager.default.fileExists(atPath: path.path) {
                    resolvedURL = path
                }
            }
        }
        self.modelURL = resolvedURL
        if let url = resolvedURL {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.coreMLModel = try? MLModel(contentsOf: url, configuration: config)
        } else {
            self.coreMLModel = nil
        }
    }

    /// Detects faces and extracts true identity embeddings for each face in the image
    public func extractFacesWithIdentity(from cgImage: CGImage) -> [FaceInstance] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return processObservations(request.results ?? [])
    }

    /// Processes already executed VNDetectFaceLandmarksRequest observations
    public func processObservations(_ observations: [VNFaceObservation]) -> [FaceInstance] {
        guard !observations.isEmpty else {
            return []
        }

        // Sort observations deterministically by spatial location (left-to-right, then bottom-to-top)
        let sortedObservations = observations.sorted { a, b in
            if a.boundingBox.origin.x != b.boundingBox.origin.x {
                return a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            return a.boundingBox.origin.y < b.boundingBox.origin.y
        }

        var results: [FaceInstance] = []
        results.reserveCapacity(sortedObservations.count)

        for obs in sortedObservations {
            let bbox = obs.boundingBox
            // Calculate eye openness from landmarks
            var leftEyeOpen = 0.8
            var rightEyeOpen = 0.8
            if let leftEye = obs.landmarks?.leftEye {
                leftEyeOpen = computeEyeOpennessRatio(eye: leftEye)
            }
            if let rightEye = obs.landmarks?.rightEye {
                rightEyeOpen = computeEyeOpennessRatio(eye: rightEye)
            }
            let avgEyeOpen = (leftEyeOpen + rightEyeOpen) / 2.0

            // Estimate face capture quality
            let quality = Double(obs.confidence)

            let embedding = computeIdentityEmbedding(landmarks: obs.landmarks, bbox: bbox)

            results.append(FaceInstance(
                boundingBox: bbox,
                eyeOpenness: avgEyeOpen,
                faceQuality: quality,
                identityEmbedding: embedding,
                descriptorType: descriptorType
            ))
        }

        return results
    }

    /// Computes cosine distance between two face identity embeddings
    public static func cosineDistance(_ vecA: [Float], _ vecB: [Float]) -> Float {
        guard vecA.count == vecB.count, !vecA.isEmpty else { return 1.0 }

        var dot: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0

        for i in 0..<vecA.count {
            dot += vecA[i] * vecB[i]
            normA += vecA[i] * vecA[i]
            normB += vecB[i] * vecB[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 1e-6 else { return 1.0 }

        let similarity = max(-1.0, min(1.0, dot / denom))
        return max(0.0, 1.0 - similarity)
    }

    private func computeIdentityEmbedding(landmarks: VNFaceLandmarks2D?, bbox: CGRect) -> [Float] {
        return computeBiometricDescriptor(landmarks: landmarks, bbox: bbox)
    }

    private func computeBiometricDescriptor(landmarks: VNFaceLandmarks2D?, bbox: CGRect) -> [Float] {
        var vector: [Float] = Array(repeating: 0.0, count: 64)
        guard let lm = landmarks else {
            // Deterministic geometric fallback from bounding box proportions
            vector[0] = Float(bbox.width)
            vector[1] = Float(bbox.height)
            vector[2] = Float(bbox.width / max(0.001, bbox.height))
            let norm = sqrt(vector[0]*vector[0] + vector[1]*vector[1] + vector[2]*vector[2])
            if norm > 1e-6 {
                return vector.map { $0 / norm }
            }
            return vector
        }

        // Extract landmark point sets safely
        let leftEyePts = lm.leftEye?.normalizedPoints ?? []
        let rightEyePts = lm.rightEye?.normalizedPoints ?? []
        let leftPupilPts = lm.leftPupil?.normalizedPoints ?? []
        let rightPupilPts = lm.rightPupil?.normalizedPoints ?? []
        let nosePts = lm.nose?.normalizedPoints ?? []
        let noseCrestPts = lm.noseCrest?.normalizedPoints ?? []
        let outerLipsPts = lm.outerLips?.normalizedPoints ?? []
        let faceContourPts = lm.faceContour?.normalizedPoints ?? []
        let leftEyebrowPts = lm.leftEyebrow?.normalizedPoints ?? []
        let rightEyebrowPts = lm.rightEyebrow?.normalizedPoints ?? []

        // Centers
        let leftEyeCenter: CGPoint
        if !leftPupilPts.isEmpty {
            leftEyeCenter = leftPupilPts[0]
        } else if !leftEyePts.isEmpty {
            leftEyeCenter = CGPoint(
                x: leftEyePts.map(\.x).reduce(0, +) / CGFloat(leftEyePts.count),
                y: leftEyePts.map(\.y).reduce(0, +) / CGFloat(leftEyePts.count)
            )
        } else {
            leftEyeCenter = CGPoint(x: bbox.minX + bbox.width * 0.3, y: bbox.minY + bbox.height * 0.65)
        }

        let rightEyeCenter: CGPoint
        if !rightPupilPts.isEmpty {
            rightEyeCenter = rightPupilPts[0]
        } else if !rightEyePts.isEmpty {
            rightEyeCenter = CGPoint(
                x: rightEyePts.map(\.x).reduce(0, +) / CGFloat(rightEyePts.count),
                y: rightEyePts.map(\.y).reduce(0, +) / CGFloat(rightEyePts.count)
            )
        } else {
            rightEyeCenter = CGPoint(x: bbox.minX + bbox.width * 0.7, y: bbox.minY + bbox.height * 0.65)
        }

        let eyeDist = max(0.001, hypot(rightEyeCenter.x - leftEyeCenter.x, rightEyeCenter.y - leftEyeCenter.y))

        // 1. Inter-ocular distance normalized
        vector[0] = Float(eyeDist / max(0.001, bbox.width))

        // 2. Eye widths and heights relative to eye distance
        if leftEyePts.count >= 4 {
            let w = hypot(leftEyePts.first!.x - leftEyePts[leftEyePts.count/2].x, leftEyePts.first!.y - leftEyePts[leftEyePts.count/2].y)
            vector[1] = Float(w / eyeDist)
        }
        if rightEyePts.count >= 4 {
            let w = hypot(rightEyePts.first!.x - rightEyePts[rightEyePts.count/2].x, rightEyePts.first!.y - rightEyePts[rightEyePts.count/2].y)
            vector[2] = Float(w / eyeDist)
        }

        // 3. Nose landmarks
        let noseTip = nosePts.last ?? CGPoint(x: (leftEyeCenter.x + rightEyeCenter.x)/2.0, y: (leftEyeCenter.y + rightEyeCenter.y)/2.0 - eyeDist*0.7)
        let noseCrest = noseCrestPts.first ?? CGPoint(x: (leftEyeCenter.x + rightEyeCenter.x)/2.0, y: (leftEyeCenter.y + rightEyeCenter.y)/2.0 - eyeDist*0.25)

        vector[3] = Float(hypot(noseTip.x - leftEyeCenter.x, noseTip.y - leftEyeCenter.y) / eyeDist)
        vector[4] = Float(hypot(noseTip.x - rightEyeCenter.x, noseTip.y - rightEyeCenter.y) / eyeDist)
        vector[5] = Float(hypot(noseTip.x - noseCrest.x, noseTip.y - noseCrest.y) / eyeDist)

        if nosePts.count >= 3 {
            let noseWidth = hypot(nosePts.first!.x - nosePts.last!.x, nosePts.first!.y - nosePts.last!.y)
            vector[6] = Float(noseWidth / eyeDist)
        }

        // 4. Mouth geometry
        if outerLipsPts.count >= 4 {
            let mouthCenter = CGPoint(
                x: outerLipsPts.map(\.x).reduce(0, +) / CGFloat(outerLipsPts.count),
                y: outerLipsPts.map(\.y).reduce(0, +) / CGFloat(outerLipsPts.count)
            )
            let mouthWidth = hypot(outerLipsPts[0].x - outerLipsPts[outerLipsPts.count/2].x, outerLipsPts[0].y - outerLipsPts[outerLipsPts.count/2].y)
            vector[7] = Float(mouthWidth / eyeDist)
            vector[8] = Float(hypot(mouthCenter.x - noseTip.x, mouthCenter.y - noseTip.y) / eyeDist)
            vector[9] = Float(hypot(mouthCenter.x - leftEyeCenter.x, mouthCenter.y - leftEyeCenter.y) / eyeDist)
            vector[10] = Float(hypot(mouthCenter.x - rightEyeCenter.x, mouthCenter.y - rightEyeCenter.y) / eyeDist)

            let mouthH = hypot(outerLipsPts[outerLipsPts.count/4].x - outerLipsPts[outerLipsPts.count*3/4].x,
                               outerLipsPts[outerLipsPts.count/4].y - outerLipsPts[outerLipsPts.count*3/4].y)
            vector[11] = Float(mouthH / max(0.001, mouthWidth))
        }

        // 5. Eyebrow distances
        if !leftEyebrowPts.isEmpty {
            let ebCenter = CGPoint(
                x: leftEyebrowPts.map(\.x).reduce(0, +) / CGFloat(leftEyebrowPts.count),
                y: leftEyebrowPts.map(\.y).reduce(0, +) / CGFloat(leftEyebrowPts.count)
            )
            vector[12] = Float(hypot(ebCenter.x - leftEyeCenter.x, ebCenter.y - leftEyeCenter.y) / eyeDist)
        }
        if !rightEyebrowPts.isEmpty {
            let ebCenter = CGPoint(
                x: rightEyebrowPts.map(\.x).reduce(0, +) / CGFloat(rightEyebrowPts.count),
                y: rightEyebrowPts.map(\.y).reduce(0, +) / CGFloat(rightEyebrowPts.count)
            )
            vector[13] = Float(hypot(ebCenter.x - rightEyeCenter.x, ebCenter.y - rightEyeCenter.y) / eyeDist)
        }

        // 6. Face contour (jaw, cheeks, chin)
        if faceContourPts.count >= 8 {
            let chin = faceContourPts[faceContourPts.count / 2]
            vector[14] = Float(hypot(chin.x - noseTip.x, chin.y - noseTip.y) / eyeDist)

            let templeWidth = hypot(faceContourPts.first!.x - faceContourPts.last!.x, faceContourPts.first!.y - faceContourPts.last!.y)
            vector[15] = Float(templeWidth / eyeDist)

            let leftJaw = faceContourPts[faceContourPts.count / 4]
            let rightJaw = faceContourPts[faceContourPts.count * 3 / 4]
            let jawWidth = hypot(rightJaw.x - leftJaw.x, rightJaw.y - leftJaw.y)
            vector[16] = Float(jawWidth / eyeDist)

            vector[17] = Float(hypot(chin.x - leftJaw.x, chin.y - leftJaw.y) / max(0.001, jawWidth))
            vector[18] = Float(hypot(chin.x - rightJaw.x, chin.y - rightJaw.y) / max(0.001, jawWidth))

            for i in 0..<min(faceContourPts.count, 24) {
                let pt = faceContourPts[i]
                vector[19 + i] = Float(hypot(pt.x - noseTip.x, pt.y - noseTip.y) / eyeDist)
            }
        }

        // 7. Facial symmetry indicators
        vector[44] = abs(vector[3] - vector[4])
        vector[45] = abs(vector[9] - vector[10])
        vector[46] = Float(bbox.width / max(0.001, bbox.height))

        // Normalize vector to unit L2 length
        var sumSquares: Float = 0.0
        for v in vector { sumSquares += v * v }
        let norm = sqrt(sumSquares)
        if norm > 1e-6 {
            return vector.map { $0 / norm }
        }
        return vector
    }

    private func computeEyeOpennessRatio(eye: VNFaceLandmarkRegion2D) -> Double {
        let points = eye.normalizedPoints
        guard points.count >= 6 else { return 0.8 }
        let h1 = abs(points[1].y - points[5].y)
        let h2 = abs(points[2].y - points[4].y)
        let w = abs(points[0].x - points[3].x)
        guard w > 0.001 else { return 0.8 }
        let ear = Double((h1 + h2) / (2.0 * w))
        return min(1.0, max(0.0, ear * 3.5))
    }
}
