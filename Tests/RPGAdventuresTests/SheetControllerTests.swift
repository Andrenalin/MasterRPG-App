// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG

@MainActor
struct SheetControllerTests {
    @Test func adventureSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == .item)
        #expect(model.source.itemId == itemId)
        #expect(!model.name.isEmpty)
    }

    @Test func adventureSheetWithPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true)

        if item.photoId != nil {
            let photoEntry = model.inlineEntries.first(where: { $0.sheetType == SheetModelType.photo })
            #expect(photoEntry != nil)
            #expect(photoEntry?.level == 0)
        }
    }

    @Test func adventureSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.entries.count >= 0)
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
        }
    }

    @Test func adventureSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let entries = sut.sheetEntries(root: root.rootManager!, itemId: itemId!, level: 0)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false) // Links default to hidden
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func adventureSheetLinkToAdventureModule() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let entries = sut.sheetEntries(root: root.rootManager!, itemId: itemId!, level: 0)

        for entry in entries {
            for link in entry.entries where link.source.typeId == NetworkModules.adventure {
                #expect(link.level == 1)
                #expect(link.isShown == false)
            }
        }
    }

    @Test func adventureSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let modelShown = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func adventureSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        // Test isFolded at level > 4
        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 5, isShown: true)
        #expect(model.isFolded == true)
        #expect(model.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 4, isShown: true)
        #expect(modelNotFolded.isFolded == false)
    }

    @Test func adventureSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.adventure)
        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: destination, level: 0, isShown: true)

        #expect(model.destination.itemId == destination.itemId)
    }
}
#endif
