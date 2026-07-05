// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import MapRPG

@MainActor
struct SheetControllerTests {
    func linkRegisterController(for root: MapRootModel) -> LinkRegisterController {
        LinkRegisterController(root: RootManager.init(anyRoot: root))
    }

    @Test func mapSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        if item.photoId != nil {
            let photoEntry = model.inlineEntries.first(where: { $0.sheetType == SheetModelType.photo })
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

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count >= 0)
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
        }
    }

    @Test func mapSheetEntriesFilterHexGrid() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

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

        let item = root.itemController.itemOrEmpty(for: itemId!)

        // Test that the main sheet has photoInline if the item has a photo
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)

        if item.photoId != nil {
            #expect(model.inlineEntries.count == 1)
            #expect(model.inlineEntries.first?.sheetType == SheetModelType.photo)
        } else {
            #expect(model.inlineEntries.isEmpty)
        }
    }

    @Test func mapSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

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

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

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

        let modelShown = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func mapSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        // Test isFolded at moduleDepth >= 1
        let modelFolded = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func mapSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.map)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId!, destination: destination, level: 0, isShown: true, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
    }
}
#endif
