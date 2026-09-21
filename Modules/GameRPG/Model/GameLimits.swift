// @copyright André Trettin

import Foundation

/// Limits that must stay identical wherever they are enforced. See CODE_AUDIT_15 §9.20.
enum GameLimits {
    /// Largest single Map/Photo/PDF/Space/Audio attachment the game moves around. The LAN framer
    /// (`GameProtocol`) and the SharePlay journal budget both bound messages by it.
    static let maximumMessageBytes = 512_000_000
}

/// `@AppStorage` keys read in more than one view.
enum GameStorageKeys {
    static let lastSelectedGameType = "lastSelectedGameType"
    static let lastAdventureUUID = "lastAdventureUUID"
}
