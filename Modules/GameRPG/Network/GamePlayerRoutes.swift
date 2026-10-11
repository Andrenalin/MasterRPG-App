// @copyright André Trettin

import CoreRPG
import Foundation

/// Which physical peer speaks for which player, on the device that hosts the game.
///
/// A LAN connection or a SharePlay participant is bound to the first sender it speaks for and
/// keeps that identity until it is removed. The transport uses the table the other way round to
/// reach one player: only that player's connection on the local network, the Journal for a
/// SharePlay participant.
struct GamePlayerRoutes: Sendable {
    private var playersByConnection: [UUID: UUID] = [:]
    private var rolesByConnection: [UUID: GameType] = [:]
    private var originsByPlayer: [UUID: GameMessageOrigin] = [:]
    private var retiredConnectionIds = PhysicalIdentityDenylist<UUID>(capacity: 256)

    /// Binds a physical origin to the sender it speaks for. An origin that already speaks for a
    /// sender cannot change identity, and a second origin cannot take over a bound sender.
    /// Origins without a physical identity (Journal, the co-located player) are always accepted.
    mutating func bind(_ origin: GameMessageOrigin, to sender: GameSenderModel) -> Bool {
        guard let connectionId = origin.participantConnectionId else { return true }
        guard !retiredConnectionIds.contains(connectionId) else { return false }
        if let existingPlayerId = playersByConnection[connectionId] {
            return existingPlayerId == sender.id && rolesByConnection[connectionId] == sender.role
        }
        guard !playersByConnection.contains(where: { $0.value == sender.id }) else { return false }
        playersByConnection[connectionId] = sender.id
        rolesByConnection[connectionId] = sender.role
        originsByPlayer[sender.id] = origin
        return true
    }

    /// Lifts a retirement for exactly the physical identity the system reported as active
    /// again. SharePlay can reissue a departed participant's id to the same device on rejoin.
    mutating func reinstate(connectionId: UUID) {
        retiredConnectionIds.remove(connectionId)
    }

    /// Retires the connection and returns the player it spoke for.
    @discardableResult
    mutating func remove(connectionId: UUID) -> UUID? {
        retiredConnectionIds.insert(connectionId)
        rolesByConnection[connectionId] = nil
        guard let playerId = playersByConnection.removeValue(forKey: connectionId) else { return nil }
        originsByPlayer[playerId] = nil
        return playerId
    }

    func playerId(for connectionId: UUID) -> UUID? {
        playersByConnection[connectionId]
    }

    func origin(for playerId: UUID) -> GameMessageOrigin? {
        originsByPlayer[playerId]
    }

    mutating func reset() {
        playersByConnection.removeAll()
        rolesByConnection.removeAll()
        originsByPlayer.removeAll()
        retiredConnectionIds.removeAll()
    }
}
