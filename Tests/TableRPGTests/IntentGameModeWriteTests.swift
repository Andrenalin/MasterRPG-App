// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_Since_3.0.1 §5.2: during a running game, intents wrote only to game memory and
/// still reported success. They now write to the library, and refuse an item the game has loaded.
@Suite("Intent writes during a game")
@MainActor
struct IntentGameModeWriteTests {
    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
    }

    private func addTable(_ root: TableRootModel, name: String) async -> UUID {
        let id = await root.itemController.addNew(type: .item)
        root.editController.reset(name: name, itemId: id)
        return id
    }

    /// Puts a session copy of `itemId` into game memory, as a game start does for its items.
    private func loadIntoGame(_ itemId: UUID, of root: TableRootModel) throws {
        let model = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        root.itemController.itemDataModel.gameItemData[itemId] = model.copy()
    }

    private func library(_ itemId: UUID, of root: TableRootModel) -> TableModel? {
        root.itemController.itemSync(for: itemId, noGame: true)
    }

    @Test("A created item reaches the library, not only game memory")
    func createIsStoredInLibrary() {
        let root = makeRoot()
        let data = root.itemController.itemDataModel
        data.isGameMode = true

        // What the Create intents did before: the item only lived in game memory.
        let lost = TableModel(id: UUID(), name: "Lost", entries: [])
        root.itemController.replace(model: lost, isInsert: true)
        #expect(data.gameItemData[lost.id] != nil)
        #expect(!data.items.contains(lost.id))

        let created = TableModel(id: UUID(), name: "Goblin King", entries: [])
        root.itemController.replace(model: created, isInsert: true, forceSave: true)
        #expect(data.items.contains(created.id))
        #expect(library(created.id, of: root)?.name == "Goblin King")
        #expect(data.gameItemData[created.id] == nil)
    }

    @Test("Updating an item the game does not use changes the library")
    func updateOutsideGamePersists() async throws {
        let root = makeRoot()
        let tableId = await addTable(root, name: "Loot")
        root.itemController.itemDataModel.isGameMode = true

        let changed = try await updateIntentItem(id: tableId, name: "Treasure", description: nil, addTags: ["gold"], removeTags: nil, in: root)

        #expect(changed)
        #expect(library(tableId, of: root)?.name == "Treasure")
        #expect(library(tableId, of: root)?.tags == ["gold"])
        #expect(root.itemController.itemDataModel.gameItemData[tableId] == nil)
    }

    @Test("Updating an item the game uses is refused and changes nothing")
    func updateInGameIsRefused() async throws {
        let root = makeRoot()
        let tableId = await addTable(root, name: "Loot")
        root.itemController.itemDataModel.isGameMode = true
        try loadIntoGame(tableId, of: root)

        await #expect(throws: ItemInGameError.self) {
            try await updateIntentItem(id: tableId, name: "Treasure", description: nil, addTags: nil, removeTags: nil, in: root)
        }
        #expect(library(tableId, of: root)?.name == "Loot")
        #expect(root.itemController.itemSync(for: tableId)?.name == "Loot", "the game copy is untouched too")
    }

    @Test("Adding an entry to an item the game does not use changes the library")
    func addEntryOutsideGamePersists() async throws {
        let root = makeRoot()
        let tableId = await addTable(root, name: "Loot")
        root.itemController.itemDataModel.isGameMode = true

        try requireOutsideGame([tableId], in: root)
        root.editController.add(entry: TableEntryModel(id: UUID(), name: "Ruby", content: ""), itemId: tableId, forceSave: true)

        #expect(library(tableId, of: root)?.entries.map(\.name) == ["Ruby"])
        #expect(root.itemController.itemDataModel.gameItemData[tableId] == nil)
    }

    @Test("Trashing items the game does not use moves them to the trash in the library")
    func trashOutsideGamePersists() async throws {
        let root = makeRoot()
        let tableId = await addTable(root, name: "Loot")
        root.itemController.itemDataModel.isGameMode = true

        try await trashIntentItems(ids: [tableId], ofType: TableEntity.self, in: root)

        #expect(library(tableId, of: root)?.displayState == DisplayStateMask.totalHidden.rawValue)
    }

    @Test("Trashing is refused for all items when the game uses one of them")
    func trashWithGameItemIsRefused() async throws {
        let root = makeRoot()
        let freeId = await addTable(root, name: "Loot")
        let gameId = await addTable(root, name: "Encounters")
        root.itemController.itemDataModel.isGameMode = true
        try loadIntoGame(gameId, of: root)

        await #expect(throws: ItemInGameError.self) {
            try await trashIntentItems(ids: [freeId, gameId], ofType: TableEntity.self, in: root)
        }
        #expect(library(freeId, of: root)?.displayState != DisplayStateMask.totalHidden.rawValue)
        #expect(library(gameId, of: root)?.displayState != DisplayStateMask.totalHidden.rawValue)
    }

    /// CODE_AUDIT_Since_3.0.1 §5.4: a Delete intent trashed a folder but left its children live.
    @Test("Trashing a folder by intent also trashes everything below it")
    func trashFolderTakesChildren() async throws {
        let root = makeRoot()
        let edit = root.editController
        let folderId = try #require(await edit.addNew(type: .folder)?.id)
        let innerId = try #require(await edit.addNew(type: .folder)?.id)
        let childId = await addTable(root, name: "Loot")
        let grandchildId = await addTable(root, name: "Encounters")
        let outsideId = await addTable(root, name: "Weather")
        edit.addItem(itemId: childId, parentId: folderId)
        edit.addItem(itemId: innerId, parentId: folderId)
        edit.addItem(itemId: grandchildId, parentId: innerId)

        try await trashIntentItems(ids: [folderId], ofType: TableEntity.self, in: root)

        let trashed = DisplayStateMask.totalHidden.rawValue
        for id in [folderId, innerId, childId, grandchildId] {
            #expect(library(id, of: root)?.displayState == trashed)
        }
        #expect(library(outsideId, of: root)?.displayState != trashed)
    }

    @Test("A folder is not trashed when the game uses one of its children")
    func trashFolderWithGameChildIsRefused() async throws {
        let root = makeRoot()
        let edit = root.editController
        let folderId = try #require(await edit.addNew(type: .folder)?.id)
        let childId = await addTable(root, name: "Loot")
        edit.addItem(itemId: childId, parentId: folderId)
        root.itemController.itemDataModel.isGameMode = true
        try loadIntoGame(childId, of: root)

        await #expect(throws: ItemInGameError.self) {
            try await trashIntentItems(ids: [folderId], ofType: TableEntity.self, in: root)
        }
        #expect(library(folderId, of: root)?.displayState != DisplayStateMask.totalHidden.rawValue)
    }

    @Test("Without a game, writes behave as before")
    func noGameUnchanged() async throws {
        let root = makeRoot()
        let tableId = await addTable(root, name: "Loot")

        try requireOutsideGame([tableId], in: root)
        try await updateIntentItem(id: tableId, name: "Treasure", description: nil, addTags: nil, removeTags: nil, in: root)

        #expect(library(tableId, of: root)?.name == "Treasure")
    }
}
