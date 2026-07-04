// @copyright André Trettin

import Foundation

enum RPGMessageType: Int, Codable, Hashable, Sendable {
    // both
    case reveal = 1
    case store = 2
    case update = 3
}

extension RPGMessageType: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .reveal:
            return "Reveal"
        case .store:
            return "Store"
        case .update:
            return "Update"
        }
    }
}
