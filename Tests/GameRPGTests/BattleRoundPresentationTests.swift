// @copyright André Trettin

import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Battle round presentation")
struct BattleRoundPresentationTests {
    @Test("Card snapshots preserve stable order and precompute participant state")
    func cardPresentations() throws {
        let model = BattleRoundPreviewData.model()

        let cards = model.cardPresentations
        let activeCard = try #require(cards.first)

        #expect(cards.map(\.rank) == Array(1...cards.count))
        #expect(activeCard.isActive)
        #expect(activeCard.defenders.count == 2)
        #expect(activeCard.attacker.rolls.map(\.total) == [17])
        #expect(activeCard.defenders.first?.rolls.map(\.total) == [9])
        #expect(activeCard.defenders.first?.isRollRecipient == true)
    }
}
