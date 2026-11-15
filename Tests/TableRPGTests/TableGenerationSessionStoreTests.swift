// @copyright André Trettin

import Foundation
import Testing

@testable import TableRPG

/// CODE_AUDIT_26 §5.44: which dice results may change a table generation.
@Suite("Table generation session store")
struct TableGenerationSessionStoreTests {
    private let player = UUID()
    private let other = UUID()

    @Test("A roll nobody waits for is not applied")
    func rollWithoutPendingStateIsIgnored() {
        #expect(!TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: false, awaitingPlayerId: nil, senderId: player))
        #expect(!TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: false, awaitingPlayerId: player, senderId: player))
    }

    @Test("A roll handed to one player only counts from that player")
    func rollFromAnotherPlayerIsIgnored() {
        #expect(TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: true, awaitingPlayerId: player, senderId: player))
        #expect(!TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: true, awaitingPlayerId: player, senderId: other))
        #expect(!TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: true, awaitingPlayerId: player, senderId: nil))
    }

    @Test("A roll handed to everyone counts from any player")
    func rollForAnyPlayerIsAccepted() {
        #expect(TableGenerationSessionStore.accepts(isAwaitingPlayerRoll: true, awaitingPlayerId: nil, senderId: other))
    }
}
