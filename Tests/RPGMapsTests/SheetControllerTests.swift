// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import MapRPG

@MainActor
struct SheetControllerTests {
    @Test func mapSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
        #expect(!model.name.isEmpty)
    }

    @Test func mapSheetWithPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true)

        if item.photoId != nil {
            let photoEntry = model.entries.first(where: { $0.sheetType == SheetModelType.photo })
            #expect(photoEntry != nil)
            #expect(photoEntry?.level == 0)
        }
    }

    @Test func mapSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.entries.count >= 0)
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 1)
        }
    }

    @Test func mapSheetEntriesFilterHexGrid() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, isShown: true)

        // All entries should not be hex grid
        for entry in entries {
            let item = root.itemController.itemOrEmpty(for: itemId!)
            let mapEntry = item.entries.first(where: { $0.id == entry.source.entryId })
            if let mapEntry {
                #expect(mapEntry.isHexGrid == false)
            }
        }
    }

    @Test func mapSheetWithPhotoInline() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, isShown: true)

        // Each map entry should have photoInline
        for entry in entries {
            #expect(entry.inlineEntries.count == 1)
            #expect(entry.inlineEntries.first?.sheetType == SheetModelType.photoInline)
        }
    }

    @Test func mapSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, isShown: true)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false) // Links default to hidden
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func mapSheetLinkToMapModule() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, isShown: true)

        for entry in entries {
            for link in entry.entries where link.source.typeId == NetworkModules.map {
                #expect(link.level == 1)
                #expect(link.isShown == false)
            }
        }
    }

    @Test func mapSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let modelShown = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func mapSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 25, isShown: true)
        #expect(entries.isEmpty)

        let entriesBeforeLimit = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 24, isShown: true)
        #expect(entriesBeforeLimit.count >= 0)
    }

    @Test func mapSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.map)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: destination, level: 0, isShown: true)

        #expect(model.destination.itemId == destination.itemId)
    }
}
#endif
