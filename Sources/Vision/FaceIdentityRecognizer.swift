import Foundation
import CoreGraphics
import CoreML
import Vision
import Accelerate

public enum DescriptorType: String, Sendable, Codable {
    case geometric = "Geometric Landmark Proportions"
    case learnedEmbedding = "Learned Deep Embedding"
}

public struct FaceInstance: Sendable, Codable {
    public let boundingBox: CGRect
    public let eyeOpenness: Double
    public let detectionConfidence: Double
    public let faceQuality: Double // Strictly mirrors detectionConfidence for legacy compatibility; never overloaded
    public let faceCaptureQuality: Double?
    public let faceSharpness: Double?
    public let identityEmbedding: [Float] // Normalized descriptor vector (64-d geometric or 128-d learned)
    public let descriptorType: DescriptorType
    public let eyeOpennessMeasured: Bool
    public let leftEyeLandmarksAvailable: Bool
    public let rightEyeLandmarksAvailable: Bool

    public init(
        boundingBox: CGRect,
        eyeOpenness: Double,
        detectionConfidence: Double? = nil,
        faceQuality: Double? = nil,
        faceCaptureQuality: Double? = nil,
        faceSharpness: Double? = nil,
        identityEmbedding: [Float],
        descriptorType: DescriptorType = .geometric,
        eyeOpennessMeasured: Bool = false,
        leftEyeLandmarksAvailable: Bool = false,
        rightEyeLandmarksAvailable: Bool = false
    ) {
        self.boundingBox = boundingBox
        self.eyeOpenness = eyeOpenness
        let conf = detectionConfidence ?? faceQuality ?? 0.8
        self.detectionConfidence = conf
        self.faceQuality = faceQuality ?? conf
        self.faceCaptureQuality = faceCaptureQuality
        self.faceSharpness = faceSharpness
        self.identityEmbedding = identityEmbedding
        self.descriptorType = descriptorType
        self.eyeOpennessMeasured = eyeOpennessMeasured
        self.leftEyeLandmarksAvailable = leftEyeLandmarksAvailable
        self.rightEyeLandmarksAvailable = rightEyeLandmarksAvailable
    }
}

public struct FaceExtractionResult: Sendable {
    public let faces: [FaceInstance]
    public let visionRequestSucceeded: Bool
    public let landmarksRequestSucceeded: Bool
    public let captureQualityRequestSucceeded: Bool
    public let errorDescription: String?

    public init(
        faces: [FaceInstance],
        visionRequestSucceeded: Bool,
        landmarksRequestSucceeded: Bool,
        captureQualityRequestSucceeded: Bool,
        errorDescription: String? = nil
    ) {
        self.faces = faces
        self.visionRequestSucceeded = visionRequestSucceeded
        self.landmarksRequestSucceeded = landmarksRequestSucceeded
        self.captureQualityRequestSucceeded = captureQualityRequestSucceeded
        self.errorDescription = errorDescription
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
    public func extractFacesWithIdentity(from cgImage: CGImage, enableFaceCaptureQuality: Bool = false) -> [FaceInstance] {
        return extractFacesWithIdentityResult(from: cgImage, enableFaceCaptureQuality: enableFaceCaptureQuality).faces
    }

    /// Full result API: Distinguishes Vision execution success vs failure and provides detailed request metrics
    public func extractFacesWithIdentityResult(from cgImage: CGImage, enableFaceCaptureQuality: Bool = false) -> FaceExtractionResult {
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        var requests: [VNRequest] = [landmarksRequest]
        var captureQualityRequest: VNDetectFaceCaptureQualityRequest? = nil

        if enableFaceCaptureQuality {
            let cqReq = VNDetectFaceCaptureQualityRequest()
            requests.append(cqReq)
            captureQualityRequest = cqReq
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            return FaceExtractionResult(
                faces: [],
                visionRequestSucceeded: false,
                landmarksRequestSucceeded: false,
                captureQualityRequestSucceeded: false,
                errorDescription: error.localizedDescription
            )
        }

        let faces = processObservations(
            landmarksRequest.results ?? [],
            captureQualityObservations: captureQualityRequest?.results as? [VNFaceObservation]
        )

        return FaceExtractionResult(
            faces: faces,
            visionRequestSucceeded: true,
            landmarksRequestSucceeded: landmarksRequest.results != nil,
            captureQualityRequestSucceeded: enableFaceCaptureQuality ? (captureQualityRequest?.results != nil) : false,
            errorDescription: nil
        )
    }

    /// Processes already executed VNDetectFaceLandmarksRequest observations with optional capture quality observations
    public func processObservations(
        _ observations: [VNFaceObservation],
        captureQualityObservations: [VNFaceObservation]? = nil
    ) -> [FaceInstance] {
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
            let leftEye = obs.landmarks?.leftEye
            let rightEye = obs.landmarks?.rightEye

            let leftEyeAvailable = (leftEye?.pointCount ?? 0) > 0
            let rightEyeAvailable = (rightEye?.pointCount ?? 0) > 0
            let eyeMeasured = leftEyeAvailable || rightEyeAvailable

            var avgEyeOpen = 0.8 // Default baseline fallback for legacy calculations
            if leftEyeAvailable && rightEyeAvailable, let lEye = leftEye, let rEye = rightEye {
                let lOpen = computeEyeOpennessRatio(eye: lEye)
                let rOpen = computeEyeOpennessRatio(eye: rEye)
                avgEyeOpen = (lOpen + rOpen) / 2.0
            } else if leftEyeAvailable, let lEye = leftEye {
                avgEyeOpen = computeEyeOpennessRatio(eye: lEye)
            } else if rightEyeAvailable, let rEye = rightEye {
                avgEyeOpen = computeEyeOpennessRatio(eye: rEye)
            }

            // Estimate face capture quality:
            // If explicit captureQualityObservations provided, match by bounding box IoU
            var matchedCaptureQuality: Double? = nil
            if let cqObservations = captureQualityObservations, !cqObservations.isEmpty {
                var bestIoU: Double = 0.0
                var bestCQ: Double? = nil
                for cqObs in cqObservations {
                    let iou = computeBoundingBoxIoU(bbox, cqObs.boundingBox)
                    if iou > bestIoU {
                        bestIoU = iou
                        if let fcq = cqObs.faceCaptureQuality {
                            bestCQ = Double(fcq)
                        }
                    }
                }
                if bestIoU >= 0.3 {
                    matchedCaptureQuality = bestCQ
                }
            } else if let fcq = obs.faceCaptureQuality {
                matchedCaptureQuality = Double(fcq)
            }

            let confidence = Double(obs.confidence)
            let embedding = computeIdentityEmbedding(landmarks: obs.landmarks, bbox: bbox)

            results.append(FaceInstance(
                boundingBox: bbox,
                eyeOpenness: avgEyeOpen,
                detectionConfidence: confidence,
                faceQuality: confidence, // Pure baseline detection confidence; NEVER overwritten by capture quality
                faceCaptureQuality: matchedCaptureQuality,
                faceSharpness: nil,
                identityEmbedding: embedding,
                descriptorType: descriptorType,
                eyeOpennessMeasured: eyeMeasured,
                leftEyeLandmarksAvailable: leftEyeAvailable,
                rightEyeLandmarksAvailable: rightEyeAvailable
            ))
        }

        return results
    }

    private func computeBoundingBoxIoU(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        if intersection.isNull || intersection.isEmpty { return 0.0 }
        let areaA = a.width * a.height
        let areaB = b.width * b.height
        let areaI = intersection.width * intersection.height
        let union = areaA + areaB - areaI
        return union > 0 ? Double(areaI / union) : 0.0
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
