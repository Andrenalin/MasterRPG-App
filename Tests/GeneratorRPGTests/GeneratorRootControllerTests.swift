// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

@MainActor
struct GeneratorRootControllerTests {
    @Test func exportControllerCollectsNestedGeneratorItems() async throws {
        let root = GeneratorRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Prompt Folder", itemId: folderId, forceSave: false)
        root.editController.reset(name: "Nested Prompt", itemId: childId, forceSave: false)
        root.itemController.itemOrEmpty(for: folderId).entries.append(ChildEntryModel(id: UUID(), childId: childId))

        let exported = root.exportController.exporting(itemIds: ItemModuleIds(ids: Set([folderId]), module: .generator))
        let generatorIds = try #require(exported.ids[.generator])
        #expect(Set(generatorIds) == Set([folderId, childId]))
    }

    @Test func sheetGameEditSearchImportAndLinkControllers() async throws {
        let root = GeneratorRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Prompt", itemId: itemId, forceSave: false)
        root.editController.reset(description: "Original description", itemId: itemId, forceSave: false)

        let rootManager = RootManager(anyRoot: root)
        let sheet = root.sheetController.sheet(
            root: rootManager,
            itemId: itemId,
            destination: nil,
            level: 2,
            isShown: true,
            moduleDepth: 0,
            isEditor: false
        )
        #expect(sheet.name == "Prompt")
        #expect(sheet.description == "Original description")
        #expect(sheet.level == 2)
        #expect(sheet.isShown == true)
        #expect(sheet.source.itemId == itemId)
        #expect(sheet.source.typeId == .generator)

        root.editController.reset(name: "Prompt Revised", itemId: itemId, forceSave: false)
        root.sheetController.update(root: rootManager, sheetModel: sheet, isEditor: false)
        #expect(sheet.name == "Prompt Revised")
        #expect(sheet.hasChanged)

        let referenceId = UUID()
        // Through the generic save: the module setter had no production caller (CODE_AUDIT_Edit_Save §9.7).
        let model = root.itemController.itemOrEmpty(for: itemId).copy()
        model.referenceId = referenceId
        root.editController.save(updated: model, message: "Reference added", forceSave: false)
        #expect(root.itemController.itemOrEmpty(for: itemId).referenceId == referenceId)

        root.gameController.setGame(item: root.itemController.itemOrEmpty(for: itemId), itemId: itemId)
        #expect(root.gameController.gameItem(for: itemId).id == itemId)
        #expect(root.gameController.currentItem().id == itemId)
        #expect(root.gameController.itemControllable is ItemController)
        #expect(root.gameController.exportControllable is ExportController)

        #expect(root.searchController.itemControllable is ItemController)
        #expect(root.importController.itemControllable is ItemController)
        #expect(root.importController.editControllable is EditController)

        let linked = root.linkController.toggleTextLink(
            linkNumber: 1,
            itemId: itemId,
            entryId: nil,
            command: nil,
            in: "keep me",
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        #expect(linked == "keep me")
        #expect(root.linkController.itemControllable is ItemController)
    }
}
#endif
