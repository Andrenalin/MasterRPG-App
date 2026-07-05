// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct SheetControllerTests {
    func linkRegisterController(for root: CharacterRootModel) -> LinkRegisterController {
        LinkRegisterController(root: RootManager.init(anyRoot: root))
    }
    
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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        // Character sheets with displayState == 0 should have showHeader set
        let item = root.itemController.itemOrEmpty(for: itemId!)
        if item.displayState == 0 {
            #expect(model.showHeader == true)
        } else {
            #expect(model.showHeader == false)
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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count > 0)
        // Each entry should have proper source and be at the same level
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        // Find entry with valueId (group type)
        let groupEntry = model.entries.first(where: { $0.sheetType == SheetModelType.group })
        if let groupEntry {
            #expect(groupEntry.entries.count > 0)
            #expect(groupEntry.entries.first?.isShown == false) // Value links default to hidden
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

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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
}
#endif
