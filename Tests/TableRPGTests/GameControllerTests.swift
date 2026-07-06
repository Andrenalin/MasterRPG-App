// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import TableRPG

@MainActor
struct GameControllerTests {
    @Test func resultSelectionAndGameState() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let listTableId = UUID()
        let diceTableId = UUID()
        let firstEntry = TableEntryModel.fixture(name: "First", content: "One")
        let secondEntry = TableEntryModel.fixture(name: "Second", content: "Two")
        let diceFirstEntry = TableEntryModel.fixture(name: "1-3", content: "Low")
        let diceSecondEntry = TableEntryModel.fixture(name: "4-6", content: "High")
        let listTable = TableModel(id: listTableId, name: "List", entries: [firstEntry, secondEntry])
        let diceTable = TableModel(
            id: diceTableId,
            name: "Dice",
            tableType: .dice,
            diceId: UUID(),
            entries: [diceFirstEntry, diceSecondEntry]
        )

        root.itemController.replace(model: listTable, isInsert: true)
        root.itemController.replace(model: diceTable, isInsert: true)

        sut.setGame(item: listTable.copy(), itemId: listTableId)
        sut.setGame(item: diceTable.copy(), itemId: diceTableId)

        #expect(sut.currentItem().id == diceTableId)
        #expect(sut.gameItem(for: listTableId).id == listTableId)

        #expect(sut.entry(for: listTableId, with: 1) == firstEntry.id)
        #expect(sut.entry(for: listTableId, with: 2) == secondEntry.id)
        #expect(sut.entry(for: listTableId, with: 0) == nil)
        #expect(sut.entry(for: listTableId, with: 3) == nil)
        #expect(sut.entry(for: diceTableId, with: 2) == diceFirstEntry.id)
        #expect(sut.entry(for: diceTableId, with: 5) == diceSecondEntry.id)

        sut.addResult(ResultCategory(id: listTableId, module: .table), value: "Top Level")
        #expect(sut.gameItem(for: listTableId).diceResult == "Top Level")

        sut.addResult(ResultCategory(id: listTableId, childId: secondEntry.id, module: .table), value: "Child Result")
        #expect(sut.gameItem(for: listTableId)[secondEntry.id].diceResult == "Child Result")

        sut.addResult(ResultCategory(id: listTableId, module: .map), value: "Ignored")
        #expect(sut.gameItem(for: listTableId).diceResult == "Top Level")
    }
}
