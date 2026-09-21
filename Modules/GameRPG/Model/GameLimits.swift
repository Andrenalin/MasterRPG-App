// @copyright André Trettin

import Foundation

/// Limits that must stay identical wherever they are enforced. See CODE_AUDIT_15 §9.20.
enum GameLimits {
    /// Largest single Map/Photo/PDF/Space/Audio attachment the game moves around. The LAN framer
    /// (`GameProtocol`) and the SharePlay journal budget both bound messages by it.
    static let maximumMessageBytes = 512_000_000

    /// Cumulative payload bytes the inbound message pipeline may hold queued at once (an empty
    /// queue still admits one message of any size). See CODE_AUDIT_16 §6.3.
    static let maximumQueuedBytes = 768_000_000
}

/// `@AppStorage` keys read in more than one view.
enum GameStorageKeys {
    static let lastSelectedGameType = "lastSelectedGameType"
    static let lastAdventureUUID = "lastAdventureUUID"
}
