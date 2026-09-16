import Foundation

public enum WeddingCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case bridePrep
    case groomPrep
    case ceremony
    case bride
    case groom
    case couple
    case familyAndGroups
    case guestsCandid
    case details
    case reception
    case cakeAndToast
    case danceParty
    case other

    public var id: String { rawValue }

    public var localizedNameIT: String {
        switch self {
        case .bridePrep: return "Preparazione sposa"
        case .groomPrep: return "Preparazione sposo"
        case .ceremony: return "Cerimonia"
        case .bride: return "Sposa"
        case .groom: return "Sposo"
        case .couple: return "Coppia"
        case .familyAndGroups: return "Gruppi e famiglia"
        case .guestsCandid: return "Invitati / candid"
        case .details: return "Location e dettagli"
        case .reception: return "Ricevimento"
        case .cakeAndToast: return "Torta e brindisi"
        case .danceParty: return "Ballo / festa"
        case .other: return "Altro"
        }
    }

    public var localizedNameEN: String {
        switch self {
        case .bridePrep: return "Bride Preparation"
        case .groomPrep: return "Groom Preparation"
        case .ceremony: return "Ceremony"
        case .bride: return "Bride"
        case .groom: return "Groom"
        case .couple: return "Couple"
        case .familyAndGroups: return "Family & Groups"
        case .guestsCandid: return "Guests & Candid"
        case .details: return "Location & Details"
        case .reception: return "Reception"
        case .cakeAndToast: return "Cake & Toast"
        case .danceParty: return "Dance & Party"
        case .other: return "Other"
        }
    }

    public var displayName: String {
        let isItalian = Locale.current.language.languageCode?.identifier == "it"
        return isItalian ? localizedNameIT : localizedNameEN
    }

    public var iconName: String {
        switch self {
        case .bridePrep: return "wand.and.stars"
        case .groomPrep: return "tshirt"
        case .ceremony: return "heart.circle"
        case .bride: return "person.crop.circle"
        case .groom: return "person.fill"
        case .couple: return "figure.2.arms.open"
        case .familyAndGroups: return "person.3.sequence"
        case .guestsCandid: return "person.2.slash"
        case .details: return "camera.macro"
        case .reception: return "fork.knife"
        case .cakeAndToast: return "birthday.cake"
        case .danceParty: return "music.note"
        case .other: return "photo.on.rectangle"
        }
    }

    /// Category base importance weight for selection quotas
    public var selectionWeight: Double {
        switch self {
        case .ceremony: return 1.5
        case .couple: return 1.4
        case .cakeAndToast: return 1.3
        case .bride: return 1.2
        case .groom: return 1.2
        case .bridePrep: return 1.1
        case .groomPrep: return 1.1
        case .familyAndGroups: return 1.1
        case .danceParty: return 1.0
        case .reception: return 0.9
        case .details: return 0.9
        case .guestsCandid: return 0.8
        case .other: return 0.7
        }
    }
}
