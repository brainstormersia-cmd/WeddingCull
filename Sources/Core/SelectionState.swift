import Foundation

public enum SelectionState: String, Codable, Sendable, CaseIterable {
    case selected
    case alternative
    case review
    case rejected
    case userSelected
    case userRejected

    public var isUserOverride: Bool {
        switch self {
        case .userSelected, .userRejected:
            return true
        case .selected, .alternative, .review, .rejected:
            return false
        }
    }

    public var isIncludedInFinal: Bool {
        switch self {
        case .selected, .userSelected:
            return true
        case .alternative, .review, .rejected, .userRejected:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .selected:
            return "Selected"
        case .alternative:
            return "Alternative"
        case .review:
            return "Review"
        case .rejected:
            return "Rejected"
        case .userSelected:
            return "Selected (User)"
        case .userRejected:
            return "Rejected (User)"
        }
    }

    public var badgeColorName: String {
        switch self {
        case .selected, .userSelected:
            return "green"
        case .alternative:
            return "orange"
        case .review:
            return "blue"
        case .rejected, .userRejected:
            return "gray"
        }
    }
}
