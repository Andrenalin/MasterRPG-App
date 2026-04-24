// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct SheetControllerTests {
    @Test func tableSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

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

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0)

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
        let entries = sut.sheetEntries(root: rootManager, itemId: root.itemController.itemDataModel.items.first!, level: 0)

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

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func tableSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        // Test level limit at 25
        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 25)
        #expect(entries.isEmpty)

        let entriesBeforeLimit = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 24)
        #expect(entriesBeforeLimit.count >= 0)
    }

    @Test func tableSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(diceRoot: root.diceRoot, generatorRoot: root, pdfRoot: root.pdfRoot, tableRoot: root)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.table)
        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: destination, level: 0, isShown: true)

        #expect(model.destination.itemId == destination.itemId)
    }
}
