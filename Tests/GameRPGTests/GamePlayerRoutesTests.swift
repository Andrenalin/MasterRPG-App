// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// Which connection or SharePlay participant speaks for which player.
@Suite("Game player routes")
struct GamePlayerRoutesTests {
    func sender(_ id: UUID = UUID(), role: GameType = .player) -> GameSenderModel {
        GameSenderModel(id: id, role: role, name: "Player", characterId: nil)
    }

    @Test("The first message binds a connection to its player")
    func bindRegistersPlayer() {
        // Given
        var routes = GamePlayerRoutes()
        let connectionId = UUID()
        let player = sender()

        // When
        let bound = routes.bind(.direct(connectionId), to: player)

        // Then
        #expect(bound)
        #expect(routes.playerId(for: connectionId) == player.id)
        #expect(routes.origin(for: player.id) == .direct(connectionId))
    }

    @Test("A SharePlay participant is a route of its own kind")
    func sharePlayParticipantRoute() {
        // Given
        var routes = GamePlayerRoutes()
        let participantId = UUID()
        let player = sender()

        // When
        let bound = routes.bind(.sharePlay(participantId), to: player)

        // Then
        #expect(bound)
        #expect(routes.origin(for: player.id) == .sharePlay(participantId))
    }

    @Test("A connection cannot change the player or the role it speaks for")
    func boundConnectionKeepsItsIdentity() {
        // Given
        var routes = GamePlayerRoutes()
        let connectionId = UUID()
        let player = sender()
        _ = routes.bind(.direct(connectionId), to: player)

        // When
        let samePlayer = routes.bind(.direct(connectionId), to: player)
        let otherPlayer = routes.bind(.direct(connectionId), to: sender())
        let otherRole = routes.bind(.direct(connectionId), to: sender(player.id, role: .observer))

        // Then
        #expect(samePlayer)
        #expect(!otherPlayer)
        #expect(!otherRole)
        #expect(routes.playerId(for: connectionId) == player.id)
    }

    @Test("A second connection cannot take over a bound player")
    func competingConnectionIsRejected() {
        // Given
        var routes = GamePlayerRoutes()
        let first = UUID()
        let second = UUID()
        let player = sender()
        _ = routes.bind(.direct(first), to: player)

        // When
        let takeover = routes.bind(.direct(second), to: player)

        // Then
        #expect(!takeover)
        #expect(routes.playerId(for: second) == nil)
        #expect(routes.origin(for: player.id) == .direct(first))
    }

    @Test("A player reconnects on a new connection after the old one was removed")
    func reconnectOnNewConnection() {
        // Given
        var routes = GamePlayerRoutes()
        let old = UUID()
        let new = UUID()
        let other = UUID()
        let player = sender()
        let otherPlayer = sender()
        _ = routes.bind(.direct(old), to: player)
        _ = routes.bind(.direct(other), to: otherPlayer)

        // When
        let removed = routes.remove(connectionId: old)
        let routeAfterRemoval = routes.origin(for: player.id)
        let reconnected = routes.bind(.direct(new), to: player)

        // Then
        #expect(removed == player.id)
        #expect(routeAfterRemoval == nil)
        #expect(reconnected)
        #expect(routes.origin(for: player.id) == .direct(new))
        #expect(routes.playerId(for: other) == otherPlayer.id)
    }

    @Test("A removed connection rejects the messages still in flight")
    func removedConnectionStaysRetired() {
        // Given
        var routes = GamePlayerRoutes()
        let connectionId = UUID()
        let player = sender()
        _ = routes.bind(.direct(connectionId), to: player)
        routes.remove(connectionId: connectionId)

        // When
        let lateMessage = routes.bind(.direct(connectionId), to: player)

        // Then
        #expect(!lateMessage)
    }

    @Test("A SharePlay participant the system reports as active again can bind again")
    func reinstatedParticipantBindsAgain() {
        // Given
        var routes = GamePlayerRoutes()
        let participantId = UUID()
        let player = sender()
        _ = routes.bind(.sharePlay(participantId), to: player)
        routes.remove(connectionId: participantId)

        // When
        routes.reinstate(connectionId: participantId)
        let rejoined = routes.bind(.sharePlay(participantId), to: player)

        // Then
        #expect(rejoined)
        #expect(routes.origin(for: player.id) == .sharePlay(participantId))
    }

    @Test("The co-located player, who has no connection, is accepted and binds nothing")
    func anonymousOriginsBindNothing() {
        // Given
        var routes = GamePlayerRoutes()
        let player = sender()

        // When
        let local = routes.bind(.direct(nil), to: player)

        // Then
        #expect(local)
        #expect(routes.origin(for: player.id) == nil)
    }

    @Test("Removing an unknown connection returns no player")
    func removingUnknownConnection() {
        // Given
        var routes = GamePlayerRoutes()

        // When
        let removed = routes.remove(connectionId: UUID())

        // Then
        #expect(removed == nil)
    }
}
#endif
