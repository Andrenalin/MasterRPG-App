// @copyright André Trettin

import Foundation
import Synchronization
import Testing

@testable import CoreRPG

@MainActor
struct GameShareReportTests {
    @Test("Nothing is shared with everyone while the game has no players")
    func withoutPlayersNothingIsShared() {
        let sut = FakeItemRootControllerFixture(sharingViewType: .share).root.gameControllable

        #expect(!sut.isSharedWithEveryone(.fixture1))
    }

    @Test("An item is shared with everyone once the master and each player reported it")
    func sharedOnceEveryoneReported() {
        let sut = FakeItemRootControllerFixture(sharingViewType: .share).root.gameControllable
        let masterId = UUID()
        let playerId = UUID()
        let otherPlayerId = UUID()
        sut.gameModel.setCurrent(players: [masterId, playerId, otherPlayerId])

        sut.report(itemId: .fixture1, for: playerId)
        sut.report(itemId: .fixture1, for: otherPlayerId)
        #expect(!sut.isSharedWithEveryone(.fixture1))

        // A share button that read the state is told when the last report arrives.
        let didChange = Mutex(false)
        withObservationTracking {
            _ = sut.isSharedWithEveryone(.fixture1)
        } onChange: {
            didChange.withLock { $0 = true }
        }
        sut.report(itemId: .fixture1, for: masterId)

        #expect(didChange.withLock { $0 })
        #expect(sut.isSharedWithEveryone(.fixture1))
        #expect(!sut.isSharedWithEveryone(.fixture2))
    }

    @Test("A player that left no longer holds the share back")
    func departedPlayerIsNotAwaited() {
        let sut = FakeItemRootControllerFixture(sharingViewType: .share).root.gameControllable
        let masterId = UUID()
        let playerId = UUID()
        let departedPlayerId = UUID()
        sut.gameModel.setCurrent(players: [masterId, playerId, departedPlayerId])
        sut.report(itemId: .fixture1, for: masterId)
        sut.report(itemId: .fixture1, for: playerId)
        #expect(!sut.isSharedWithEveryone(.fixture1))

        sut.gameModel.setCurrent(players: [masterId, playerId])

        #expect(sut.isSharedWithEveryone(.fixture1))
    }
}
