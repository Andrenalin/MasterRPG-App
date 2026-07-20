// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
@testable import CharacterRPG
@testable import DiceRPG
import Foundation
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG
import Testing

@Suite("Character game controller tests")
@MainActor
struct GameControllerTests {

    @Test("Game state helpers expose current item, photos, player pin and dice focus")
    func gameStateHelpers() async throws {
        let root = Self.makeRoot()
        let sut = root.gameController
        let diceId = UUID()
        let photoId = UUID()
        let entryId = UUID()
        let characterId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "Strike", type: .number, value: "12", diceId: diceId)
        let character = ValueModel(id: characterId, name: "Mira", category: .character, photoId: photoId, photos: [photoId], entries: [entry])
        root.itemController.replace(model: character, isInsert: true)

        sut.setGame(item: character.copy(), itemId: characterId)
        #expect(sut.currentItem().id == characterId)
        #expect(sut.gameItem(for: characterId).name == "Mira")
        let renamedCharacter = ValueModel(id: characterId, name: "Mira Updated", category: .character, photoId: photoId, photos: [photoId], entries: [entry])
        sut.setGame(item: renamedCharacter, itemId: characterId)
        #expect(sut.gameItem(for: characterId).name == "Mira Updated")
        #expect(sut.imageIds(for: characterId) == [photoId])
        #expect(sut.playerPinPhoto(for: characterId) == photoId)

        await sut.startGame(for: characterId)
        #expect(sut.gameModel.focusItemIds == [characterId])

        let firstEntryDice = try #require(sut.focusDice(for: characterId))
        let reusedEntryDice = try #require(sut.focusDice(for: characterId))
        #expect(reusedEntryDice == firstEntryDice)

        sut.resetGameDiceId(itemId: characterId, entryId: entryId)
        let resetEntryDice = try #require(sut.focusDice(for: characterId))
        #expect(resetEntryDice != firstEntryDice)

        let directDiceCharacterId = UUID()
        let directDiceCharacter = ValueModel(id: directDiceCharacterId, name: "Kara", category: .character, diceId: diceId)
        root.itemController.replace(model: directDiceCharacter, isInsert: true)
        let directDice = try #require(sut.focusDice(for: directDiceCharacterId))
        let reusedDirectDice = try #require(sut.focusDice(for: directDiceCharacterId))
        #expect(reusedDirectDice == directDice)
        #expect(root.diceRoot.diceGameControllable.gameModel.itemData[directDice] != nil)
    }

    @Test("Update player accepts complete value payloads and rejects invalid payloads")
    func updatePlayer() async throws {
        let root = Self.makeRoot()
        let sut = root.gameController
        let itemId = UUID()
        root.itemController.replace(model: ValueModel(id: itemId, name: "Remote Hero", category: .character), isInsert: true)

        let payload = try await sut.createGameData(for: itemId)
        try await sut.updatePlayer(data: payload)

        let idOnlyValue = NetworkCodableDataType(id: itemId, type: .value, version: 0)
        await #expect(throws: ItemGameStorableError.wrongData) {
            try await sut.updatePlayer(data: idOnlyValue)
        }

        await #expect(throws: ItemGameStorableError.wrongData) {
            try await sut.updatePlayer(data: NetworkCodableDataType(id: UUID(), type: .photo, version: 0))
        }
    }
}

private extension GameControllerTests {
    static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
}
#endif
