// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

@MainActor
struct EditControllerTests {

    // Returns the current set of item IDs in the controller.
    private func idSet(_ root: AudioRootModel) -> Set<UUID> {
        Set(root.itemController.itemDataModel.items)
    }

    // Returns the single new item ID that appeared after the operation, failing the test if count ≠ 1.
    private func requireSingleNewId(before: Set<UUID>, in root: AudioRootModel) throws -> UUID {
        let added = idSet(root).subtracting(before)
        return try #require(added.first, "Expected exactly one new item but found \(added.count)")
    }

    // MARK: - duplicate

    @Test("Duplicating a normal item copies all properties except id — name gets Copy suffix, fileUrl is nil")
    func duplicatingNormalItemCopiesAllPropertiesExceptId() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track A", itemId: itemId, forceSave: false)
        root.editController.reset(description: "A cool track", itemId: itemId, forceSave: false)
        root.editController.reset(tags: ["rock", "loud"], itemId: itemId, forceSave: false)
        let original = root.itemController.itemOrEmpty(for: itemId)

        let before = idSet(root)
        await root.editController.duplicate(item: original)
        let dupId = try requireSingleNewId(before: before, in: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != original.id)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.description == original.description)
        #expect(dup.tags == original.tags)
        #expect(dup.category == original.category)
        #expect(dup.displayState == original.displayState)
        #expect(dup.fileUrl == nil)
        #expect(dup.parentId == original.parentId)
    }

    @Test("Duplicating a collection copies all properties; entries keep references to the same child items")
    func duplicatingCollectionCopiesAllPropertiesAndKeepsEntryReferences() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let playlistId = await root.itemController.addNew(type: .playlist)
        root.editController.reset(name: "My Playlist", itemId: playlistId, forceSave: false)
        root.editController.reset(tags: ["chill"], itemId: playlistId, forceSave: false)
        let trackId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track A", itemId: trackId, forceSave: false)
        root.editController.addItem(itemId: trackId, parentId: playlistId)

        let original = root.itemController.itemOrEmpty(for: playlistId)
        try #require(original.entries.count == 1)

        let before = idSet(root)
        await root.editController.duplicate(item: original)
        let dupId = try requireSingleNewId(before: before, in: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != playlistId)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.category == .playlist)
        #expect(dup.tags == original.tags)
        #expect(dup.entries.count == original.entries.count)
        // Collection entries are references — both playlists reference the same track
        #expect(dup.entries.map(\.audioId) == original.entries.map(\.audioId))
    }

    @Test("Duplicating a folder creates a new folder with independently duplicated children — not the original child IDs")
    func duplicatingFolderDuplicatesChildrenIntoNewFolder() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Folder A", itemId: folderId, forceSave: false)
        let child1Id = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track 1", itemId: child1Id, forceSave: false)
        root.editController.addItem(itemId: child1Id, parentId: folderId)
        let child2Id = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track 2", itemId: child2Id, forceSave: false)
        root.editController.addItem(itemId: child2Id, parentId: folderId)

        let original = root.itemController.itemOrEmpty(for: folderId)
        try #require(original.entries.count == 2)

        let before = idSet(root)
        await root.editController.duplicate(item: original)
        let newIds = idSet(root).subtracting(before)

        // A new folder must appear among the new IDs
        let dupFolderId = try #require(newIds.first {
            root.itemController.itemOrEmpty(for: $0).category == .folder
        })
        let dupFolder = root.itemController.itemOrEmpty(for: dupFolderId)
        #expect(dupFolder.id != folderId)
        #expect(dupFolder.name.hasSuffix("Copy"))
        #expect(dupFolder.category == .folder)
        #expect(dupFolder.parentId == original.parentId)
        #expect(dupFolder.entries.count == 2)

        // New folder's entries must reference new child items, not the originals
        let dupChildIds = Set(dupFolder.entries.map(\.audioId))
        #expect(!dupChildIds.contains(child1Id))
        #expect(!dupChildIds.contains(child2Id))
        for childId in dupChildIds {
            let child = root.itemController.itemOrEmpty(for: childId)
            #expect(child.parentId == dupFolderId)
        }
    }

    @Test("Duplicating an item inside a folder: duplicate keeps the same parentId and is added to the parent folder")
    func duplicatingItemInFolderPreservesParentAndIsAddedToFolder() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Folder A", itemId: folderId, forceSave: false)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track A", itemId: itemId, forceSave: false)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.parentId == folderId)

        let before = idSet(root)
        await root.editController.duplicate(item: item)
        let dupId = try requireSingleNewId(before: before, in: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        // Duplicate preserves the parent folder
        #expect(dup.parentId == folderId)
        // Parent folder's entries must include the new duplicate
        let folder = root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.contains(where: { $0.childId == dupId }))
    }

    @Test("Duplicating a collection member adds the new item as a child reference in that collection")
    func duplicatingCollectionMemberAddsNewReferenceToCollection() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let playlistId = await root.itemController.addNew(type: .playlist)
        root.editController.reset(name: "My Playlist", itemId: playlistId, forceSave: false)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Track A", itemId: itemId, forceSave: false)
        root.editController.addItem(itemId: itemId, parentId: playlistId)

        let playlist = root.itemController.itemOrEmpty(for: playlistId)
        try #require(playlist.entries.count == 1)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let before = idSet(root)
        await root.editController.duplicate(item: item)
        let dupId = try requireSingleNewId(before: before, in: root)

        // Collection must now contain both the original and the new duplicate
        let updatedPlaylist = root.itemController.itemOrEmpty(for: playlistId)
        #expect(updatedPlaylist.entries.count == 2)
        #expect(updatedPlaylist.entries.contains(where: { $0.audioId == dupId }))
    }
}
