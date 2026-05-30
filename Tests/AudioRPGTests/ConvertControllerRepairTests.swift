// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

/// Tests for ConvertController.extractFolderAndCreate function
@Suite("ConvertController extractFolderAndCreate Tests")
@MainActor
struct ConvertControllerExtractFolderTests {

    // Finds the UUID of a folder matching name + parentId, or fails the test.
    private func requireFolder(named name: String, parentId: UUID?, in root: AudioRootModel) throws -> UUID {
        try #require(root.itemController.itemDataModel.items.first {
            let m = root.itemController.itemOrEmpty(for: $0)
            return m.category == .folder && m.name == name && m.parentId == parentId
        })
    }

    @Test("url Maps/DS/Something.txt with no parentId creates Maps→DS hierarchy and places item in DS")
    func itemWithNestedUrlAndNoParentIdCreatesHierarchy() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let cc = ConvertController(itemController: root.itemController, editController: root.editController)

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Something", itemId: itemId)

        let url = URL(string: "/Maps/DS/Something.txt")!
        let item = root.itemController.itemOrEmpty(for: itemId)
        await cc.extractFolderAndCreate(url: url, item: item)

        let mapsId = try requireFolder(named: "Maps", parentId: nil, in: root)
        let dsId   = try requireFolder(named: "DS",   parentId: mapsId, in: root)

        let maps = root.itemController.itemOrEmpty(for: mapsId)
        #expect(maps.entries.contains(where: { $0.childId == dsId }))

        let ds = root.itemController.itemOrEmpty(for: dsId)
        #expect(ds.entries.contains(where: { $0.childId == itemId }))
        #expect(root.itemController.itemOrEmpty(for: itemId).parentId == dsId)
    }

    @Test("url B/Something.txt with parentId pointing to an unrelated folder creates B and moves item there")
    func itemInUnrelatedFolderIsMovedToNewFolderMatchingUrl() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let cc = ConvertController(itemController: root.itemController, editController: root.editController)

        // Pre-create an unrelated folder "Other" and place the item there
        let otherId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Other", itemId: otherId)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Something", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: otherId)
        #expect(root.itemController.itemOrEmpty(for: itemId).parentId == otherId)

        let url = URL(string: "/B/Something.txt")!
        let item = root.itemController.itemOrEmpty(for: itemId)
        await cc.extractFolderAndCreate(url: url, item: item)

        // Folder B must be created at root, item moved into it
        let bId = try requireFolder(named: "B", parentId: nil, in: root)
        let bFolder = root.itemController.itemOrEmpty(for: bId)
        #expect(bFolder.entries.contains(where: { $0.childId == itemId }))
        #expect(root.itemController.itemOrEmpty(for: itemId).parentId == bId)
    }

    @Test("url Maps/DS/Something.txt when item is already in DS — item is not moved again")
    func itemAlreadyInCorrectFolderIsNotDuplicated() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let cc = ConvertController(itemController: root.itemController, editController: root.editController)

        // Pre-create Maps→DS hierarchy and place the item in DS
        let mapsId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Maps", itemId: mapsId)
        let dsId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "DS", itemId: dsId)
        root.editController.addItem(itemId: dsId, parentId: mapsId)

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Something", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: dsId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.parentId == dsId)

        let url = URL(string: "/Maps/DS/Something.txt")!
        await cc.extractFolderAndCreate(url: url, item: item)

        // parentId unchanged and item appears exactly once in DS
        #expect(root.itemController.itemOrEmpty(for: itemId).parentId == dsId)
        let ds = root.itemController.itemOrEmpty(for: dsId)
        #expect(ds.parentId == mapsId)
        #expect(ds.entries.filter({ $0.childId == itemId }).count == 1)
    }
}

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
