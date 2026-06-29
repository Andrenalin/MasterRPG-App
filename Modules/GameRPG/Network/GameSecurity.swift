// @copyright André Trettin

/// Shared security constants for MasterRPG peer-to-peer pairing.
/// The passcode derives the TLS pre-shared key used by both NWListener and NWConnection
/// so only MasterRPG peers can pair on the local network.
enum GameSecurity {
    static let passcode = "GameMasterCode"
}
