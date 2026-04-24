// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct SheetControllerTests {
    @Test func characterSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        // Create RootManager for testing
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.name == "Adalbert Unheil")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
    }

    @Test func characterSheetWithPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        // Character with displayState == 0 should have photo in inlineEntries
        if model.showHeader {
            let photoEntry = model.inlineEntries.first(where: { $0.sheetType == SheetModelType.photo })
            #expect(photoEntry != nil)
        }
    }

    @Test func characterSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.entries.count > 0)
        // Each entry should have proper source
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 1)
        }
    }

    @Test func characterSheetWithValueLink() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        // Find entry with valueId (group type)
        let groupEntry = model.entries.first(where: { $0.sheetType == SheetModelType.group })
        if let groupEntry {
            #expect(groupEntry.entries.count > 0)
            #expect(groupEntry.entries.first?.isShown == true) // Value links are shown
        }
    }

    @Test func characterSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func characterSheetWithDice() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        // Find entry with diceId
        let entryWithDice = model.entries.first(where: { !$0.inlineEntries.isEmpty })
        if let entryWithDice {
            let diceInline = entryWithDice.inlineEntries.first(where: { $0.sheetType == SheetModelType.dice })
            #expect(diceInline != nil)
        }
    }

    @Test func characterSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        // Test level limit at 25
        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 25)
        #expect(entries.isEmpty)

        let entriesBeforeLimit = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 24)
        #expect(entriesBeforeLimit.count > 0)
    }
}
#endif
