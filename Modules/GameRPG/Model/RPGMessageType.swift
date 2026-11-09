// @copyright André Trettin

import Foundation

/// How a game message reaches the item.
///
/// Wire format: the raw values travel in every envelope and decode strictly. A peer that does
/// not know a case cannot decode the envelope and drops it, with a decode error and no hint
/// about the version. Adding, removing or renumbering a case therefore changes the wire format:
/// bump `GameNetworkModel.currentVersion` with it (a peer of another version is refused with an
/// explicit "unsupported version" instead). `WireContractTests` pins the cases and the version
/// together so that neither changes alone. See CODE_AUDIT_Game_Shareplay §4.1.
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
