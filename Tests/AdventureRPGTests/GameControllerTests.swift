// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import DiceRPG
@testable import MapRPG

@MainActor
struct GameControllerTests {
    @Test func adventureGameLifecycleAndDiceFocus() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let itemId = UUID()
        let diceId = UUID()
        let adventure = AdventureModel(id: itemId, name: "Quest", diceId: diceId)
        let noDiceAdventure = AdventureModel(id: UUID(), name: "Quiet Quest")

        root.itemController.replace(model: adventure, isInsert: true)
        root.itemController.replace(model: noDiceAdventure, isInsert: true)

        sut.setGame(item: adventure.copy(), itemId: itemId)
        #expect(sut.currentItem().id == itemId)
        #expect(sut.gameItem(for: itemId).name == "Quest")

        let focusedDiceId = try #require(sut.focusDice(for: itemId))
        #expect(root.diceRoot.gameController.gameModel.items.contains(focusedDiceId))
        #expect(sut.focusDice(for: noDiceAdventure.id) == nil)

        await sut.startGame(with: itemId)
        #expect(sut.gameModel.focusItemIds == [itemId])

        _ = sut.saveGame()
        await sut.resetGame()
        #expect(sut.gameModel.items.isEmpty)
        #expect(root.diceRoot.gameController.gameModel.items.isEmpty)
        #expect(root.mapRoot.gameController.gameModel.items.isEmpty)
    }
}
