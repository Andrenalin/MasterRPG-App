// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

@Suite("Table players: who gets a player pin")
struct TablePlayerResolverTests {
    let heroId = UUID()
    let mageId = UUID()
    let rogueId = UUID()

    func name(_ characterId: UUID) -> String? {
        switch characterId {
        case heroId: "Hero"
        case mageId: "Mage"
        default: nil
        }
    }

    @Test func connectedPlayersComeFirstAndObserversNeverGetAPin() {
        let player = PlayerGameModel(id: UUID(), type: .player, name: "Anna", characterId: UUID())
        let observer = PlayerGameModel(id: UUID(), type: .observer, name: "Observer")
        let hero = TablePlayerModel(characterId: heroId)

        let result = TablePlayerResolver.pinPlayers(roster: [observer, player], tablePlayers: [hero], name: name)

        #expect(result.map(\.id) == [player.id, hero.id])
        #expect(result[1] == PlayerGameModel(id: hero.id, type: .player, name: "Hero", characterId: heroId))
    }

    @Test func disabledAndMissingCharactersGetNoPin() {
        let disabled = TablePlayerModel(characterId: heroId, isEnabled: false)
        let missing = TablePlayerModel(characterId: rogueId)
        let mage = TablePlayerModel(characterId: mageId)

        let result = TablePlayerResolver.pinPlayers(roster: [], tablePlayers: [disabled, missing, mage], name: name)

        #expect(result.map(\.id) == [mage.id])
    }

    @Test func aConnectedPlayerTakesOverTheCharacterUntilLeaving() {
        let hero = TablePlayerModel(characterId: heroId)
        let anna = PlayerGameModel(id: UUID(), type: .player, name: "Anna", characterId: heroId)

        let claimed = TablePlayerResolver.pinPlayers(roster: [anna], tablePlayers: [hero], name: name)
        #expect(claimed.map(\.id) == [anna.id])
        #expect(TablePlayerResolver.status(of: hero, roster: [anna], characterExists: true) == .claimed(by: "Anna"))

        let afterLeaving = TablePlayerResolver.pinPlayers(roster: [], tablePlayers: [hero], name: name)
        #expect(afterLeaving.map(\.id) == [hero.id])
        #expect(TablePlayerResolver.status(of: hero, roster: [], characterExists: true) == .active)
    }

    @Test func anObserverDoesNotClaimACharacter() {
        let hero = TablePlayerModel(characterId: heroId)
        let observer = PlayerGameModel(id: UUID(), type: .observer, name: "Observer", characterId: heroId)

        let result = TablePlayerResolver.pinPlayers(roster: [observer], tablePlayers: [hero], name: name)

        #expect(result.map(\.id) == [hero.id])
        #expect(TablePlayerResolver.status(of: hero, roster: [observer], characterExists: true) == .active)
    }

    @Test func oneCharacterGetsOnePin() {
        let first = TablePlayerModel(characterId: heroId)
        let second = TablePlayerModel(characterId: heroId)

        let result = TablePlayerResolver.pinPlayers(roster: [], tablePlayers: [first, second], name: name)

        #expect(result.map(\.id) == [first.id])
    }

    @Test func statusOfDisabledAndMissing() {
        let disabled = TablePlayerModel(characterId: heroId, isEnabled: false)
        #expect(TablePlayerResolver.status(of: disabled, roster: [], characterExists: true) == .disabled)
        #expect(TablePlayerResolver.status(of: disabled, roster: [], characterExists: false) == .missing)
    }

    @Test func addingSkipsCharactersAlreadyAtTheTable() {
        let hero = TablePlayerModel(characterId: heroId, isEnabled: false)

        let result = TablePlayerResolver.adding(characterIds: [heroId, mageId, mageId], to: [hero])

        #expect(result.count == 2)
        #expect(result[0] == hero)
        #expect(result[1].characterId == mageId)
        #expect(result[1].isEnabled)
    }
}
#endif
