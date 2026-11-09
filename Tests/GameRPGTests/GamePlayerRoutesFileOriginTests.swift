// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.6: a Journal attachment has no participant to bind to.
@Suite("Player routes and Journal files")
struct GamePlayerRoutesFileOriginTests {
    private func player(_ id: UUID = UUID()) -> GameSenderModel {
        GameSenderModel(id: id, role: .player, name: "Player", characterId: nil)
    }

    @Test("A file of a sender this device never heard from is refused")
    func unknownSenderIsRefused() {
        var routes = GamePlayerRoutes()
        let stranger = player()

        let accepted = routes.bind(.file, to: stranger)

        #expect(!accepted)
        #expect(!routes.isBound(.file, to: stranger.id))
    }

    @Test("A file of a player that speaks over a SharePlay participant is accepted")
    func knownSenderIsAccepted() {
        var routes = GamePlayerRoutes()
        let sender = player()
        let bound = routes.bind(.sharePlay(UUID()), to: sender)

        let accepted = routes.bind(.file, to: sender)

        #expect(bound)
        #expect(accepted)
        #expect(routes.isBound(.file, to: sender.id))
    }

    @Test("A file that arrives after its player left is refused")
    func lateFileOfALostPlayerIsRefused() {
        var routes = GamePlayerRoutes()
        let sender = player()
        let participantId = UUID()
        let bound = routes.bind(.sharePlay(participantId), to: sender)
        routes.remove(connectionId: participantId)

        let accepted = routes.bind(.file, to: sender)

        #expect(bound)
        #expect(!accepted)
        #expect(!routes.isBound(.file, to: sender.id))
    }
}
#endif
