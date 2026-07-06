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

    @Test("Add item attaches a duplicated value under the character adventure group")
    func addItem() async throws {
        let root = Self.makeRoot()
        let sut = root.gameController
        let characterId = UUID()
        let itemId = UUID()
        let character = ValueModel(id: characterId, name: "Mira", category: .character)
        let item = ValueModel(id: itemId, name: "Lantern", category: .item)
        root.itemController.replace(model: character, isInsert: true)
        root.itemController.replace(model: item, isInsert: true)

        let itemData = try await sut.createGameData(for: itemId)
        await sut.addItem(id: itemId, data: itemData, for: characterId)

        let updatedCharacter = root.itemController.itemOrEmpty(for: characterId)
        let adventureValueId = try #require(updatedCharacter.entries.first { $0.valueId != nil }?.valueId)
        let adventureValue = root.itemController.itemOrEmpty(for: adventureValueId)
        let linkedValueIds = adventureValue.entries.compactMap(\.valueId)
        #expect(linkedValueIds.contains { root.itemController.itemOrEmpty(for: $0).name == "Lantern" })
    }

    @Test("Value results create and add entry and model payloads")
    func createAndAddResults() async throws {
        let root = Self.makeRoot()
        let sut = root.gameController
        let characterId = UUID()
        let character = ValueModel(id: characterId, name: "Mira", category: .character)
        root.itemController.replace(model: character, isInsert: true)
        let resultCategory = ResultCategory(id: UUID(), module: .table)

        let entryData = sut.create(name: "Clue", value: "The door is warm", resultCategory: resultCategory)
        let entryResult = try #require(ValueResultModel.decodeData(of: entryData.data))
        #expect(entryResult.valueEntryModels.first?.name == "Clue")
        #expect(entryResult.valueEntryModels.first?.value == "The door is warm")

        await sut.add(result: entryData, for: characterId)
        let updatedCharacter = root.itemController.itemOrEmpty(for: characterId)
        let adventureValueId = try #require(updatedCharacter.entries.first { $0.valueId != nil }?.valueId)
        let adventureValue = root.itemController.itemOrEmpty(for: adventureValueId)
        #expect(adventureValue.entries.contains { $0.name == "Clue" })

        let modelData = sut.create(
            name: "Treasure",
            description: "Glittering coins",
            entries: [("Coins", "12"), ("Gems", "2")],
            resultCategory: resultCategory
        )
        let modelResult = try #require(ValueResultModel.decodeData(of: modelData.data))
        #expect(modelResult.valueModels.first?.name == "Treasure")
        #expect(modelResult.valueModels.first?.entries.count == 2)

        await sut.add(result: modelData, for: characterId)
        let addedNames = root.itemController.itemDataModel.items.map { root.itemController.itemOrEmpty(for: $0).name }
        #expect(addedNames.contains("Treasure"))

        let invalidData = NetworkCodableDataType(id: UUID(), type: .value, version: 0)
        await sut.add(result: invalidData, for: characterId)
    }

    @Test("Update player accepts value payloads and rejects wrong modules")
    func updatePlayer() async throws {
        let root = Self.makeRoot()
        let sut = root.gameController
        let itemId = UUID()
        root.itemController.replace(model: ValueModel(id: itemId, name: "Remote Hero", category: .character), isInsert: true)

        let payload = try await sut.createGameData(for: itemId)
        try await sut.updatePlayer(data: payload)

        let idOnlyValue = NetworkCodableDataType(id: itemId, type: .value, version: 0)
        try await sut.updatePlayer(data: idOnlyValue)

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
