// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

/// CODE_AUDIT_26 §10.4: duplication with groups and folders, the table-players save during a
/// game and the merge of folder variants. They carry data-loss potential.
@Suite("Adventure controller risks")
@MainActor
struct AdventureControllerRiskTests {
    private func makeRoot() async throws -> AdventureRootModel {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()
        return root
    }

    @Test("Duplicating an adventure copies its group, remaps groupId and adventureId, and leaves the original")
    func duplicateAdventureWithGroup() async throws {
        let root = try await makeRoot()
        let controller = root.itemController
        let parentId = await controller.addNew(type: .adventure)
        let groupId = await controller.addNew(type: .adventure)
        root.editController.reset(name: "Campaign", itemId: parentId)
        root.editController.reset(name: "Act One", itemId: groupId)
        let group = try #require(controller.itemSync(for: groupId, noGame: true))
        group.groupId = parentId
        controller.replace(model: group, isInsert: false)
        let parent = try #require(controller.itemSync(for: parentId, noGame: true))
        parent.entries = [AdventureEntryModel(id: UUID(), name: "Scene", content: "", adventureId: groupId)]
        controller.replace(model: parent, isInsert: false)
        let before = Set(controller.itemDataModel.items)

        await root.editController.duplicate(item: parent)

        let created = Set(controller.itemDataModel.items).subtracting(before)
        #expect(created.count == 2, "the copy and the copy of its group")
        let copies = created.compactMap { controller.itemSync(for: $0, noGame: true) }
        let copyParent = try #require(copies.first { $0.groupId == nil })
        let copyGroup = try #require(copies.first { $0.groupId != nil })
        #expect(copyGroup.groupId == copyParent.id, "the group copy belongs to the parent copy")
        #expect(copyParent.entries.first?.adventureId == copyGroup.id, "the entry points at the group copy")
        #expect(copyGroup.id != groupId)
        // The original is untouched.
        let originalParent = try #require(controller.itemSync(for: parentId, noGame: true))
        #expect(originalParent.entries.first?.adventureId == groupId)
        #expect(controller.itemSync(for: groupId, noGame: true)?.groupId == parentId)
    }

    @Test("Duplicating a folder copies its sub-folder and their members, each under its own copy")
    func duplicateFolderWithSubFolder() async throws {
        let root = try await makeRoot()
        let controller = root.itemController
        let folderId = await controller.addNew(type: .folder)
        let subId = await controller.addNew(type: .folder)
        let leafId = await controller.addNew(type: .adventure)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Sub", itemId: subId)
        root.editController.reset(name: "Leaf", itemId: leafId)
        root.editController.addItem(itemId: subId, parentId: folderId)
        root.editController.addItem(itemId: leafId, parentId: subId)
        let before = Set(controller.itemDataModel.items)
        let folder = try #require(controller.itemSync(for: folderId, noGame: true))

        await root.editController.duplicate(item: folder)

        let created = Set(controller.itemDataModel.items).subtracting(before)
        #expect(created.count == 3, "folder, sub-folder and leaf are copied")
        let copies = created.compactMap { controller.itemSync(for: $0, noGame: true) }
        let copyFolder = try #require(copies.first { $0.isFolder && $0.parentId == nil })
        let copySub = try #require(copies.first { $0.isFolder && $0.parentId == copyFolder.id })
        let copyLeaf = try #require(copies.first { !$0.isFolder })
        #expect(copyLeaf.parentId == copySub.id)
        #expect(copyFolder.entries.map(\.childId) == [copySub.id])
        #expect(copySub.entries.map(\.childId) == [copyLeaf.id])
        // The original structure is intact.
        #expect(controller.itemSync(for: subId, noGame: true)?.parentId == folderId)
        #expect(controller.itemSync(for: leafId, noGame: true)?.parentId == subId)
    }

    @Test("Saving table players during a game updates the library and the game copy, not the rest of the session")
    func saveTablePlayersDuringGame() async throws {
        let root = try await makeRoot()
        let controller = root.itemController
        let adventureId = await controller.addNew(type: .adventure)
        root.editController.reset(name: "Journey", itemId: adventureId)
        let library = try #require(controller.itemSync(for: adventureId, noGame: true))
        root.gameController.setGame(item: library.copy(), itemId: adventureId)
        controller.itemDataModel.isGameMode = true
        let gameItem = try #require(controller.itemDataModel.gameItemData[adventureId] as? AdventureModel)
        gameItem.name = "Session name"
        let players = [TablePlayerModel(characterId: UUID()), TablePlayerModel(characterId: UUID(), isEnabled: false)]

        root.gameController.saveTablePlayers(players, for: adventureId)

        #expect(root.gameController.tablePlayers(for: adventureId) == players, "the library holds the players")
        #expect(gameItem.tablePlayers == players, "the loaded game copy mirrors them")
        #expect(gameItem.name == "Session name", "the session's own change is not overwritten by the library")
        #expect(controller.itemSync(for: adventureId, noGame: true)?.name == "Journey")

        // The same list again changes nothing.
        root.gameController.saveTablePlayers(players, for: adventureId)
        #expect(gameItem.tablePlayers == players)
    }

    @Test("Two variants of a folder merge to the union of their members, in either order")
    func mergeOfFolderVariants() {
        let id = UUID()
        let sharedChild = UUID(), localChild = UUID(), remoteChild = UUID()
        let local = AdventureModel(id: id, name: "Folder", category: .folder, entries: [
            .newChild(id: sharedChild), .newChild(id: localChild)
        ])
        let remote = AdventureModel(id: id, name: "Folder", category: .folder, entries: [
            .newChild(id: sharedChild), .newChild(id: remoteChild)
        ])

        let forward = local.merge(remote)
        let backward = remote.merge(local)

        #expect(Set(forward.entries.map(\.childId)) == [sharedChild, localChild, remoteChild])
        #expect(Set(backward.entries.map(\.childId)) == Set(forward.entries.map(\.childId)))
        #expect(forward.entries.map(\.childId).filter { $0 == sharedChild }.count == 1)
    }
}
#endif
