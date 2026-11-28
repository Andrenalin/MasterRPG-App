// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_Folder §5: import and game-delivery fixes, with TableRPG as the host module.
@MainActor
struct ImportGameAuditTests {
    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
    }

    private func addTable(_ root: TableRootModel, name: String, type: ItemListCategory = .item) -> UUID {
        let id = root.itemController.addNewSync(type: type)
        root.editController.reset(name: name, itemId: id, forceSave: false)
        return id
    }

    private func export(_ ids: Set<UUID>, from root: TableRootModel) async throws -> Data {
        let exportIds = root.exportController.exporting(itemIds: ItemModuleIds(ids: ids, module: .table))
        let stream = OutputStream.toMemory()
        stream.open()
        _ = try await root.exportController.export(itemIds: exportIds, into: stream)
        stream.close()
        return try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
    }

    private func importFile(_ data: Data, into root: TableRootModel, mode: ImportMode) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        let importModel = ItemDataImportModel(importMode: mode)
        try await root.importController.importStream(from: stream, forceSave: true, importModel: importModel)
    }

    @Test("Overwriting a folder from a subset export keeps its other children (§5.8)")
    func overwriteKeepsLocalFolderChildren() async throws {
        let root = makeRoot()
        let folderId = addTable(root, name: "Folder", type: .folder)
        let exportedId = addTable(root, name: "Exported")
        let otherId = addTable(root, name: "Other")
        root.editController.addItem(itemId: exportedId, parentId: folderId)
        root.editController.addItem(itemId: otherId, parentId: folderId)

        let data = try await export([exportedId], from: root)
        try await importFile(data, into: root, mode: .overwrite)

        let childIds = Set(root.itemController.itemSync(for: folderId)?.entries.map(\.childId) ?? [])
        #expect(childIds == [exportedId, otherId])
        #expect(root.itemController.itemSync(for: otherId)?.parentId == folderId)
    }

    @Test("An import repairs the folders of all its items in one pass (§7.3)")
    func importRepairsStaleFolderEntriesOnce() async throws {
        let root = makeRoot()
        let folderId = addTable(root, name: "Folder", type: .folder)
        let staleFolderId = addTable(root, name: "Stale", type: .folder)
        let firstId = addTable(root, name: "First")
        let secondId = addTable(root, name: "Second")
        root.editController.addItem(itemId: firstId, parentId: folderId)
        root.editController.addItem(itemId: secondId, parentId: folderId)
        let data = try await export([firstId, secondId], from: root)
        // Entries a sync merge can leave behind in another folder.
        let staleFolder = try #require(root.editController.editModel(for: staleFolderId))
        staleFolder.entries.append(contentsOf: [TableEntryModel.newChild(id: firstId), TableEntryModel.newChild(id: secondId)])
        root.editController.save(updated: staleFolder, message: "stale", forceSave: false)

        try await importFile(data, into: root, mode: .overwrite)

        #expect(root.itemController.itemSync(for: staleFolderId)?.entries.isEmpty == true)
        #expect(Set(root.itemController.itemSync(for: folderId)?.entries.map(\.childId) ?? []) == [firstId, secondId])
    }

    @Test("A merge import restores an item from the trash (§5.20)")
    func mergeImportRestoresTrashedItem() async throws {
        let root = makeRoot()
        let tableId = addTable(root, name: "Loot")
        let data = try await export([tableId], from: root)
        root.editController.markForDeletion(itemId: tableId, forceSave: false)
        #expect(root.itemController.itemSync(for: tableId)?.displayState == DisplayStateMask.totalHidden.rawValue)

        try await importFile(data, into: root, mode: .merge)

        #expect(root.itemController.itemSync(for: tableId)?.displayState == DisplayStateMask.fullVisible.rawValue)
    }

    @Test("A game import reports a table it updated in place (§5.10)")
    func gameImportReportsInPlaceUpdates() async throws {
        let master = makeRoot()
        let tableId = addTable(master, name: "Loot")
        let player = makeRoot()
        player.itemController.itemDataModel.isGameMode = true

        let first = try await player.gameController.importNetwork(from: try await export([tableId], from: master))
        #expect(first[.table]?.contains(tableId) == true)

        master.editController.reset(name: "Treasure", itemId: tableId, forceSave: false)
        let second = try await player.gameController.importNetwork(from: try await export([tableId], from: master))

        #expect(second[.table]?.contains(tableId) == true, "an in-place update of the game copy still counts as imported")
        #expect((player.gameController.gameModel.itemData[tableId] as? TableModel)?.name == "Treasure")
        #expect(player.itemController.itemSync(for: tableId, noGame: true) == nil, "a game delivery stays in game memory")
    }

    @Test("Persisting a game copy keeps the local folder and visibility (§5.23)")
    func persistFromGameKeepsLocalPlacement() throws {
        let root = makeRoot()
        let folderId = addTable(root, name: "Folder", type: .folder)
        let tableId = addTable(root, name: "Loot")
        root.editController.addItem(itemId: tableId, parentId: folderId)

        let gameCopy = try #require(root.itemController.itemSync(for: tableId, noGame: true)).copy()
        gameCopy.parentId = nil
        gameCopy.name = "Treasure"

        root.itemController.persistFromGame(model: gameCopy, authoritative: false)

        let library = try #require(root.itemController.itemSync(for: tableId, noGame: true))
        #expect(library.name == "Treasure")
        #expect(library.parentId == folderId)
    }

    @Test("An authoritative delivery is persisted as sent, in the local folder (§5.23)")
    func authoritativePersistKeepsLocalPlacement() throws {
        let root = makeRoot()
        let folderId = addTable(root, name: "Folder", type: .folder)
        let tableId = addTable(root, name: "Loot")
        root.editController.addItem(itemId: tableId, parentId: folderId)

        let gameCopy = try #require(root.itemController.itemSync(for: tableId, noGame: true)).copy()
        gameCopy.parentId = nil
        gameCopy.description = "From the master"

        root.itemController.persistFromGame(model: gameCopy, authoritative: true)

        let library = try #require(root.itemController.itemSync(for: tableId, noGame: true))
        #expect(library.description == "From the master")
        #expect(library.parentId == folderId)
    }
}

private extension ItemController {
    @MainActor func addNewSync(type: ItemListCategory) -> UUID {
        let model = TableModel.empty.copy()
        model.category = type
        resetModel(with: model)
        return model.id
    }
}
