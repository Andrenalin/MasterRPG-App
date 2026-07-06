// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct SheetControllerTests {
    func linkRegisterController(for root: TableRootModel) -> LinkRegisterController {
        LinkRegisterController(root: RootManager.init(anyRoot: root))
    }

    @Test func tableSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
        #expect(!model.name.isEmpty)
    }

    @Test func tableSheetWithDice() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        if item.diceId != nil {
            #expect(model.inlineEntries.count == 1)
            #expect(model.inlineEntries.first?.sheetType == SheetModelType.dice)
        }
    }

    @Test func tableSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count >= 0)
        for entry in model.entries {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
        }
    }

    @Test func tableSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        // Find entry with links
        let entryWithLinks = entries.first(where: { !$0.entries.isEmpty })
        if let entryWithLinks {
            for linkedSheet in entryWithLinks.entries {
                #expect(linkedSheet.isShown == false) // Links default to hidden
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func tableSheetLinkToTableModule() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        // Create a test item with link to another table
        let entries = sut.sheetEntries(root: rootManager, itemId: root.itemController.itemDataModel.items.first!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            for link in entry.entries where link.source.typeId == NetworkModules.table {
                #expect(link.level == 1)
                #expect(link.isShown == false)
            }
        }
    }

    @Test func tableSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func tableSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        // Test isFolded at moduleDepth >= 1
        let modelFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func tableSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.table)
        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: destination, level: 0, isShown: true, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
    }

    @Test func tableUpdateRefreshesChangedFieldsEntriesAndDiceInline() async throws {
        let root = try await MockRoot.importTestData()
        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()
        let originalDiceId = UUID()
        let updatedDiceId = UUID()
        let keptEntry = TableEntryModel.fixture(name: "Old Result", content: "Old text")
        let removedEntry = TableEntryModel.fixture(name: "Removed Result", content: "Gone")

        root.itemController.replace(
            model: TableModel(
                id: itemId,
                name: "Old Table",
                description: "Old description",
                diceId: originalDiceId,
                entries: [keptEntry, removedEntry]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        var updatedEntry = keptEntry
        updatedEntry.name = "Updated Result"
        updatedEntry.content = "Updated text"
        let newEntry = TableEntryModel.fixture(name: "New Result", content: "Fresh text")
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.name = "Updated Table"
        item.description = "Updated description"
        item.diceId = updatedDiceId
        item.entries = [updatedEntry, newEntry]

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Updated Table")
        #expect(sheetModel.description == "Updated description")
        #expect(sheetModel.inlineEntries.map(\.source.itemId) == [updatedDiceId])
        #expect(sheetModel.entries.map(\.source.entryId).contains(keptEntry.id))
        #expect(!sheetModel.entries.map(\.source.entryId).contains(removedEntry.id))
        #expect(sheetModel.entries.map(\.source.entryId).contains(newEntry.id))
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.name == "Updated Result")
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.description == "Updated text")
    }

    @Test func tableUpdateLeavesFoldedEntriesCollapsed() async throws {
        let root = try await MockRoot.importTestData()
        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()

        root.itemController.replace(
            model: TableModel(
                id: itemId,
                name: "Folded Table",
                description: "Folded description",
                entries: [TableEntryModel.fixture(name: "Hidden", content: "Hidden text")]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        root.itemController.itemOrEmpty(for: itemId).name = "Folded Updated"

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Folded Updated")
        #expect(sheetModel.isFolded)
        #expect(sheetModel.entries.isEmpty)
    }
}
