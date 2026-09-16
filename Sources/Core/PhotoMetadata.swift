import Foundation

public struct PhotoMetadata: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var orientation: Int
    public var captureDate: Date?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var focalLength: Double?
    public var aperture: Double?
    public var shutterSpeed: Double?
    public var iso: Int?
    public var hasGPS: Bool
    public var burstUUID: String?
    public var isCorrupt: Bool

    public init(
        width: Int = 0,
        height: Int = 0,
        orientation: Int = 1,
        captureDate: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        hasGPS: Bool = false,
        burstUUID: String? = nil,
        isCorrupt: Bool = false
    ) {
        self.width = width
        self.height = height
        self.orientation = orientation
        self.captureDate = captureDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.hasGPS = hasGPS
        self.burstUUID = burstUUID
        self.isCorrupt = isCorrupt
    }

    public var shutterSpeedFormatted: String {
        guard let speed = shutterSpeed, speed > 0 else { return "—" }
        if speed < 1.0 {
            let reciprocal = Int(round(1.0 / speed))
            return "1/\(reciprocal)s"
        } else {
            return String(format: "%.1fs", speed)
        }
    }

    public var apertureFormatted: String {
        guard let f = aperture, f > 0 else { return "—" }
        return String(format: "ƒ/%.1f", f)
    }

    public var isoFormatted: String {
        guard let i = iso else { return "—" }
        return "ISO \(i)"
    }

    public var focalLengthFormatted: String {
        guard let fl = focalLength else { return "—" }
        return String(format: "%.0fmm", fl)
    }

    public var cameraSummary: String {
        if let model = cameraModel, !model.isEmpty {
            return model
        }
        if let make = cameraMake, !make.isEmpty {
            return make
        }
        return "Unknown Camera"
    }
}
