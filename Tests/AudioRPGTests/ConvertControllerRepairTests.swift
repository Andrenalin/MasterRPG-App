// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

/// Tests for ConvertController.repairHiddenAndFolders function
/// Following Swift Testing best practices with Arrange-Act-Assert pattern
@Suite("ConvertController repairHiddenAndFolders Tests")
@MainActor
struct ConvertControllerRepairTests {

    @Test("Folder entries are ordered alphabetically after adding A and B via EditController")
    func folderEntriesOrderedAfterAdd() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let folderID = await root.itemController.addNew(type: .folder)

        let aID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "A", itemId: aID, forceSave: false)
        root.editController.addItem(itemId: aID, parentId: folderID)

        let bID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "B", itemId: bID, forceSave: false)
        root.editController.addItem(itemId: bID, parentId: folderID)

        let folder = root.itemController.itemOrEmpty(for: folderID)
        #expect(folder.entries.count == 2)
        let childNames = folder.entries.map { root.itemController.nameSync(itemId: $0.audioId) }
        #expect(childNames == ["A", "B"])
    }

    @Test("Export C, remove it, then import restores A B C in folder with only 3 items")
    func exportRemoveImportRestoresFolderWith3Items() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let folderID = await root.itemController.addNew(type: .folder)

        let aID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "A", itemId: aID, forceSave: false)
        root.editController.addItem(itemId: aID, parentId: folderID)

        let bID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "B", itemId: bID, forceSave: false)
        root.editController.addItem(itemId: bID, parentId: folderID)

        let initialOrder = root.itemController.itemOrEmpty(for: folderID).entries
            .map { root.itemController.nameSync(itemId: $0.audioId) }
        #expect(initialOrder == ["A", "B"])

        let cID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "C", itemId: cID, forceSave: false)
        root.editController.addItem(itemId: cID, parentId: folderID)

        // Export only C — folder F is included as partial (carries the entry reference back to C)
        let exportModel = ItemDataExportModel()
        let (exportTask, exportURL) = root.exportController.export(
            ids: ItemModuleIds(ids: Set([cID]), module: .audio),
            exportModel: exportModel
        )
        try await exportTask.value

        // Remove C from the folder and data model
        root.editController.removeItemFromParent(itemId: cID, oneUp: false, moveFiles: false, forceSave: false)
        await root.itemController.delete(itemId: cID)

        #expect(root.itemController.itemOrEmpty(for: folderID).entries.count == 2)

        // Import C back — import-scoped repair keeps the partial folder entry and restores C.
        let importTask = root.importController.importUrl(from: exportURL)
        try await importTask.value

        let folderAfterImport = root.itemController.itemOrEmpty(for: folderID)
        #expect(folderAfterImport.entries.count == 3)

        let childNames = folderAfterImport.entries
            .map { root.itemController.nameSync(itemId: $0.audioId) }
            .sorted()
        #expect(childNames == ["A", "B", "C"])

        let nonFolderCount = root.itemController.itemDataModel.items.filter { id in
            root.itemController.itemOrEmpty(for: id).category != .folder
        }.count
        #expect(nonFolderCount == 3)
    }

    @Test("Import repair normalizes item data without creating file path folders")
    func repairImportedItemsDoesNotCreateFoldersFromFileURL() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let sut = ConvertController(itemController: root.itemController, editController: root.editController)

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Something", itemId: itemId, forceSave: false)
        root.editController.reset(category: .music, itemId: itemId, forceSave: false)

        let item = root.itemController.itemOrEmpty(for: itemId)
        item.fileUrl = FileUrl(
            fileId: itemId,
            url: URL(filePath: "/Maps/DS/Something.mp3"),
            location: .other,
            module: "Audio",
            relativeUrl: nil
        )
        root.itemController.replace(model: item, isInsert: false)

        let initialItemCount = root.itemController.itemDataModel.items.count

        await sut.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: [itemId], forceSave: false)

        let repairedItem = root.itemController.itemOrEmpty(for: itemId)
        #expect(root.itemController.itemDataModel.items.count == initialItemCount)
        #expect(repairedItem.category == .entry)
        #expect(repairedItem.tags.contains("Music"))
        #expect(repairedItem.parentId == nil)
        #expect(root.itemController.itemDataModel.items.contains { id in
            let item = root.itemController.itemOrEmpty(for: id)
            return item.category == .folder && (item.name == "Maps" || item.name == "DS")
        } == false)
    }
}
