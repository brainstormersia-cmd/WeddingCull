import Foundation

public enum PersonRole: String, Codable, Sendable, CaseIterable {
    case unassigned
    case bride
    case groom
    case partnerA
    case partnerB
    case weddingParty
    case guest
    case custom

    public var displayName: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .bride: return "Bride"
        case .groom: return "Groom"
        case .partnerA: return "Partner A"
        case .partnerB: return "Partner B"
        case .weddingParty: return "Wedding Party"
        case .guest: return "Guest"
        case .custom: return "Custom"
        }
    }
}

public struct PersonCluster: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var role: PersonRole
    public var customRoleName: String?
    public var photoIDs: [String]
    public var isSuggestedPrimary: Bool
    public var confidence: Double
    public var representativeFaceCropURL: URL?

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        role: PersonRole = .unassigned,
        customRoleName: String? = nil,
        photoIDs: [String] = [],
        isSuggestedPrimary: Bool = false,
        confidence: Double = 0.5,
        representativeFaceCropURL: URL? = nil
    ) {
        self.id = id
        self.name = name.isEmpty ? "Person \(id.prefix(4))" : name
        self.role = role
        self.customRoleName = customRoleName
        self.photoIDs = photoIDs
        self.isSuggestedPrimary = isSuggestedPrimary
        self.confidence = confidence
        self.representativeFaceCropURL = representativeFaceCropURL
    }

    public var appearanceCount: Int {
        return photoIDs.count
    }
}
