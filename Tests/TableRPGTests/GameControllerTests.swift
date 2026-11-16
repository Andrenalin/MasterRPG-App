// @copyright André Trettin

import CoreRPG
@testable import DiceRPG
import Foundation
@testable import PdfRPG
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


        sut.addResult(ResultCategory(id: listTableId, module: .table), value: "Top Level")
        #expect(sut.gameItem(for: listTableId).diceResult == "Top Level")

        sut.addResult(ResultCategory(id: listTableId, childId: secondEntry.id, module: .table), value: "Child Result")
        #expect(sut.gameItem(for: listTableId)[secondEntry.id].diceResult == "Child Result")

        sut.addResult(ResultCategory(id: listTableId, module: .map), value: "Ignored")
        #expect(sut.gameItem(for: listTableId).diceResult == "Top Level")
    }

    @Test("Table version is stable, nonzero, and excludes transient dice results")
    func stableContentVersion() throws {
        // Given
        let itemId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let entryId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let first = TableModel(
            id: itemId,
            name: "Encounter",
            description: "Forest",
            tags: ["night"],
            tableType: .list,
            entries: [TableEntryModel(id: entryId, name: "1", content: "Wolf")]
        )
        let independentlyCreated = TableModel(
            id: itemId,
            name: "Encounter",
            description: "Forest",
            tags: ["night"],
            tableType: .list,
            entries: [TableEntryModel(id: entryId, name: "1", content: "Wolf")]
        )
        let originalVersion = first.version

        // When / Then
        #expect(originalVersion != 0)
        #expect(independentlyCreated.version == originalVersion)

        first.diceResult = "17"
        var rolledEntry = first[entryId]
        rolledEntry.diceResult = "5"
        first[entryId] = rolledEntry
        #expect(first.version == originalVersion)

        first.description = "Ruins"
        #expect(first.version != originalVersion)
    }

    @Test("Full package merges persistent Tables, caches without presentation, and resets session availability")
    func receiveTableMergesAndTracksSessionAvailability() async throws {
        // Given
        let master = makeRoot()
        let player = makeRoot()
        let itemId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let nestedId = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let entryId = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))

        let masterNested = TableModel(
            id: nestedId,
            name: "Nested",
            description: "Master nested",
            category: .entry,
            entries: []
        )
        let playerNested = masterNested.copy()
        playerNested.name = "Player nested"

        let link = master.linkController.generateLink(itemId: nestedId)
        let base = TableModel(
            id: itemId,
            name: "Base",
            description: "Base description",
            category: .entry,
            entries: [TableEntryModel(id: entryId, name: "Next", content: link)]
        )
        let masterTable = base.copy()
        masterTable.description = "Master description"
        let playerTable = base.copy()
        playerTable.name = "Player name"

        master.itemController.replace(model: masterTable, isInsert: true)
        master.itemController.replace(model: masterNested, isInsert: true)
        player.itemController.replace(model: playerTable, isInsert: true)
        player.itemController.replace(model: playerNested, isInsert: true)
        player.itemController.itemDataModel.isGameMode = true

        let package = try await master.gameController.createGameData(for: itemId)

        // When: cache the package without presenting it.
        let received = try await player.gameController.receiveTable(
            itemId: itemId,
            data: package,
            makeCurrent: false
        )

        // Then: every imported Table is CRDT-merged and records the master's
        // pre-merge version, but a store does not create a current presentation.
        #expect(received)
        #expect(player.gameController.gameModel.currentItemId == nil)
        let merged = player.gameController.gameItem(for: itemId)
        #expect(merged.name == "Player name")
        #expect(merged.description == "Master description")
        let mergedNested = player.gameController.gameItem(for: nestedId)
        #expect(mergedNested.name == "Player nested")
        #expect(mergedNested.description == "Master nested")
        #expect(player.gameController.isTableAvailable(itemId: itemId, version: package.version))
        #expect(player.gameController.isTableAvailable(itemId: nestedId, version: masterNested.version))

        // An exact ID-only reveal promotes and persists the already merged root.
        let reference = NetworkCodableDataType(id: itemId, type: .table, version: package.version)
        #expect(try await player.gameController.receiveTable(itemId: itemId, data: reference, makeCurrent: true))
        #expect(player.gameController.gameModel.currentItemId == itemId)
        let persisted = try #require(player.itemController.itemSync(for: itemId, noGame: true))
        #expect(persisted.name == "Player name")
        #expect(persisted.description == "Master description")

        let wrongVersion = package.version == Int.max ? package.version - 1 : package.version + 1
        let staleReference = NetworkCodableDataType(id: itemId, type: .table, version: wrongVersion)
        let acceptedStaleReference = try await player.gameController.receiveTable(
            itemId: itemId,
            data: staleReference,
            makeCurrent: true
        )
        #expect(!acceptedStaleReference)

        await player.gameController.reset()
        #expect(!player.gameController.isTableAvailable(itemId: itemId, version: package.version))
        let acceptedAfterReset = try await player.gameController.receiveTable(
            itemId: itemId,
            data: reference,
            makeCurrent: true
        )
        #expect(!acceptedAfterReset)
    }

    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(
            diceRoot: DiceRootModel.testRoot(),
            pdfRoot: PdfRootModel.testRoot()
        )
    }
}
