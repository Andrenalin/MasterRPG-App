// @copyright André Trettin

import Foundation

/// A cosmetic supporter acknowledgement. Supporter tiers never gate app features.
public enum SupporterTier: Int, Codable, CaseIterable, Comparable, Hashable, Identifiable, Sendable {
    case none = 0
    case bronze = 1
    case silver = 2
    case gold = 3

    public var id: Int { rawValue }

    public static func < (lhs: SupporterTier, rhs: SupporterTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var localizedName: LocalizedStringResource {
        switch self {
        case .none:
            LocalizedStringResource("Member", bundle: .module)
        case .bronze:
            LocalizedStringResource("Bronze Member Supporter", bundle: .module)
        case .silver:
            LocalizedStringResource("Silver Member Supporter", bundle: .module)
        case .gold:
            LocalizedStringResource("Gold Member Supporter", bundle: .module)
        }
    }
}
