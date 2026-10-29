// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

/// CODE_AUDIT_Folder §5: fixes that need PhotoRPG — persisted duplicates, share-extension file
/// names and closing a parent folder in the list.
@MainActor
struct FolderAuditPhotoTests {
    @Test("A duplicated folder's children are persisted with the copy as parent (§5.5)")
    func duplicatedFolderChildParentIsPersisted() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)
        await root.itemController.save()

        await root.editController.duplicate(item: try #require(root.itemController.itemSync(for: folderId)))
        await root.itemController.save()

        let copyFolderId = try #require(root.itemController.itemDataModel.items.first {
            $0 != folderId && root.itemController.itemSync(for: $0)?.isFolder == true
        })
        let copyChildId = try #require(root.itemController.itemSync(for: copyFolderId)?.entries.first?.childId)
        let stored = try #require(try await DataController(context: store.context, token: NetworkModules.photo.token).fetch(id: copyChildId) as? PhotoModel)
        #expect(stored.parentId == copyFolderId)
    }

    @Test("A healed duplicate folder member is written to the store and reaches a device that holds both rows")
    func healedDuplicateMemberIsPersistedAndSynced() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Ruines", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)
        await root.itemController.save()
        let storage = DataController(context: store.context, token: NetworkModules.photo.token)
        let beforeHeal = try #require(try await storage.fetch(id: folderId) as? PhotoModel)

        // CloudKit unioned a second row for the same member into the folder.
        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        folder.entries.append(PhotoEntryModel(id: UUID(), photoId: childId))
        #expect(folder.entries.count == 2)
        #expect(root.itemController.healDuplicateFolderMembers(itemId: folderId))
        // The save the periodic housekeeping and the app exit run.
        await root.itemController.save()

        let stored = try #require(try await storage.fetch(id: folderId) as? PhotoModel)
        #expect(stored.entries.count == 1, "the surplus row is gone from the store")
        #expect(stored.entries_.update != beforeHeal.entries_.update, "other devices only take the entries when the marker changed")

        // A second device still holding both rows receives the healed folder.
        let other = beforeHeal.copy()
        other.entries.append(PhotoEntryModel(id: UUID(), photoId: childId))
        #expect(!other.isSame(stored))
        #expect(other.replace(with: stored))
        #expect(other.entries.count == 1)
    }

    @Test("Every shared image gets its own sanitised file name (§5.11)")
    func shareFileNamesAreUniqueAndSafe() {
        let first = ShareImportPhotoController.fileName(for: "Map/Night: 1", photoId: UUID(), extension: "jpg")
        let second = ShareImportPhotoController.fileName(for: "Map/Night: 1", photoId: UUID(), extension: "jpg")
        let unnamed = ShareImportPhotoController.fileName(for: "  ", photoId: UUID(), extension: "jpg")

        #expect(first != second)
        #expect(!first.contains("/"))
        #expect(!first.contains(":"))
        #expect(first.hasSuffix(".jpg"))
        #expect(unnamed.hasPrefix("Photo-"))
    }

    @Test("Close parent folder closes it for good and removes the children (§5.13)")
    func closeParentFolderRemovesChildren() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)
        let list = root.folderListController
        list.listDisplayModel.listMode = .folder
        await list.performSearch(source: "test")
        let folderRow = try #require(list.listModel.list.first { $0.source.itemId == folderId })
        list.toggleFolder(item: folderRow)
        #expect(list.listModel.list.contains { $0.source.itemId == childId })

        list.closeParentFolder(of: childId)

        #expect(!folderRow.isOpen)
        #expect(!folderRow.lastIsOpen)
        #expect(!list.listModel.list.contains { $0.source.itemId == childId })
        await list.performSearch(source: "test")
        #expect(!folderRow.isOpen, "the next rebuild must not reopen it")
    }
}

private extension PhotoRootModel {
    /// `testRoot()` with a Core Data context, so writes reach a store the test can read back.
    static func persistentTestRoot(context: NSManagedObjectContext) -> PhotoRootModel {
        let root = PhotoRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: context, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
}

private struct InMemoryStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "FolderAuditPhotoTests-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        context = container.viewContext
    }
}
#endif
