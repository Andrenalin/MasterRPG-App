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
        root.editController.reset(name: "A", itemId: aID)
        root.editController.addItem(itemId: aID, parentId: folderID)

        let bID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "B", itemId: bID)
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
        root.editController.reset(name: "A", itemId: aID)
        root.editController.addItem(itemId: aID, parentId: folderID)

        let bID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "B", itemId: bID)
        root.editController.addItem(itemId: bID, parentId: folderID)

        let initialOrder = root.itemController.itemOrEmpty(for: folderID).entries
            .map { root.itemController.nameSync(itemId: $0.audioId) }
        #expect(initialOrder == ["A", "B"])

        let cID = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "C", itemId: cID)
        root.editController.addItem(itemId: cID, parentId: folderID)

        // Export only C — folder F is included as partial (carries the entry reference back to C)
        let exportModel = ItemDataExportModel()
        let (exportTask, exportURL) = root.exportController.export(
            ids: ItemModuleIds(ids: Set([cID]), module: .audio),
            exportModel: exportModel
        )
        try await exportTask.value

        // Remove C from the folder and data model
        root.editController.removeItemFromParent(itemId: cID, oneUp: false, moveFiles: false)
        await root.itemController.delete(itemId: cID)

        #expect(root.itemController.itemOrEmpty(for: folderID).entries.count == 2)

        // Import C back — repairHiddenAndFolders merges the partial folder entry, restoring C
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
}
