import Foundation
import CoreGraphics
import Vision

public final class FeaturePrintProvider: Sendable {
    public init() {}

    public func generateFeaturePrint(from cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    public func computeDistance(between printA: VNFeaturePrintObservation, and printB: VNFeaturePrintObservation) -> Float? {
        var distance: Float = 0.0
        do {
            try printA.computeDistance(&distance, to: printB)
            return distance
        } catch {
            return nil
        }
    }

    public func archiveFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    public func unarchiveFeaturePrint(from data: Data) -> VNFeaturePrintObservation? {
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}
