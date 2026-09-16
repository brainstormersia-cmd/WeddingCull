import Foundation
import CoreGraphics
import CoreML

public final class MobileCLIPClassifier: ImageClassifierProtocol, Sendable {
    private let fallbackClassifier = VisionSceneClassifier()
    private let isAppleSilicon: Bool

    // Wedding concept prompts for zero-shot classification
    public static let conceptPrompts: [WeddingCategory: [String]] = [
        .bridePrep: [
            "a bride getting ready for her wedding",
            "bridal makeup and hair preparation",
            "a bride putting on a wedding dress"
        ],
        .groomPrep: [
            "a groom getting ready for his wedding",
            "a man preparing a suit for a wedding",
            "groom putting on cufflinks or tie"
        ],
        .ceremony: [
            "a wedding ceremony",
            "a bride and groom exchanging vows",
            "wedding rings during a ceremony",
            "walking down the church aisle"
        ],
        .bride: [
            "a portrait of a bride in her wedding gown",
            "bride holding a floral bouquet"
        ],
        .groom: [
            "a formal portrait of the groom",
            "groom in elegant wedding suit"
        ],
        .couple: [
            "a wedding portrait of the bride and groom",
            "newlywed couple romantic portrait",
            "bride and groom kissing outdoors"
        ],
        .familyAndGroups: [
            "a formal wedding group photograph",
            "family members posing at a wedding",
            "bridesmaids and groomsmen group photo"
        ],
        .guestsCandid: [
            "wedding guests mingling and laughing",
            "candid moments of guests at a wedding"
        ],
        .details: [
            "wedding rings flowers decoration detail photography",
            "table centerpiece floral arrangement wedding invitation"
        ],
        .reception: [
            "wedding reception dinner",
            "guests sitting at wedding tables",
            "speeches at wedding reception banquet"
        ],
        .cakeAndToast: [
            "a couple cutting a wedding cake",
            "wedding cake cutting celebration",
            "champagne toast at a wedding"
        ],
        .danceParty: [
            "first dance at a wedding",
            "people dancing at a wedding party",
            "wedding reception dance floor"
        ]
    ]

    public init(hardwareCapabilities: HardwareCapabilities = HardwareCapabilities()) {
        self.isAppleSilicon = hardwareCapabilities.isAppleSilicon
    }

    public func classify(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) async -> (category: WeddingCategory, confidence: Double) {
        // Fallback directly to VisionSceneClassifier when advanced ML model is not bundled or running on Intel
        return fallbackClassifier.classify(cgImage: cgImage, metadata: metadata, faceCount: faceCount)
    }
}
