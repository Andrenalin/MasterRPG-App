// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

/// CODE_AUDIT_Folder §5: fixes that need PhotoRPG — persisted duplicates, share-extension file
/// names and closing a parent folder in the list.
// Serialized: the sync tests take the process-wide data-mutation lock, and a parallel one is refused.
@Suite(.serialized)
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

    @Test("Sync leaves out a file that went away after the plan was shown")
    func cloudFolderScanApplyDropsVanishedFile() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let files = try #require(root.itemController.fileUrlDataController)
        let top = "ScanTest-\(UUID().uuidString)"
        let topUrl = files.cloudDocumentController.moduleUrl.appending(path: top, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: topUrl) }
        for path in ["Keep.png", "Gone.png"] {
            let url = topUrl.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)
        var plan = try await scannedPlan(controller)
        plan.items.removeAll { $0.file.components.first != top }
        plan.folders.removeAll { $0.path.first != top }
        #expect(plan.items.map(\.name).sorted() == ["Gone", "Keep"])

        // The plan is on screen; the file goes before the user taps Sync.
        try FileManager.default.removeItem(at: topUrl.appending(path: "Gone.png"))
        let outcome = await controller.apply(plan)

        #expect(outcome == .synced(added: 1, folders: 1, moved: 0, trashed: 0))
        let goneId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Gone.png"], isFolder: false)
        let keepId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Keep.png"], isFolder: false)
        #expect(root.itemController.itemSync(for: goneId, noGame: true) == nil)
        #expect(root.itemController.itemSync(for: keepId, noGame: true) != nil)
    }

    @Test("Sync is refused when a game starts while it is already running")
    func cloudFolderScanApplyStopsWhenGameStartsMidway() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let files = try #require(root.itemController.fileUrlDataController)
        let top = "ScanTest-\(UUID().uuidString)"
        let topUrl = files.cloudDocumentController.moduleUrl.appending(path: top, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: topUrl) }
        try FileManager.default.createDirectory(at: topUrl, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: topUrl.appending(path: "Late.png"))
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)
        var plan = try await scannedPlan(controller)
        plan.items.removeAll { $0.file.components.first != top }
        plan.folders.removeAll { $0.path.first != top }
        #expect(plan.items.count == 1)

        // The sync runs until its first suspension (hash read, scan); the game starts there.
        let sync = Task { @MainActor in await controller.apply(plan) }
        await Task.yield()
        root.itemController.itemDataModel.isGameMode = true
        let outcome = await sync.value

        #expect(outcome == .busy)
        let lateId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Late.png"], isFolder: false)
        root.itemController.itemDataModel.isGameMode = false
        #expect(root.itemController.itemSync(for: lateId, noGame: true) == nil, "nothing reached the library")
    }

    @Test("The iCloud folder scan adds items for files without one, in the folder structure of their path")
    func cloudFolderScanAddsMissingItems() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let files = try #require(root.itemController.fileUrlDataController)
        let top = "ScanTest-\(UUID().uuidString)"
        let topUrl = files.cloudDocumentController.moduleUrl.appending(path: top, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: topUrl) }
        for path in ["Sub/One.png", "Two.png", ".Three.png.icloud", "notes.txt"] {
            let url = topUrl.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)

        // Only what this test wrote: the module folder may hold other files.
        var plan = try await scannedPlan(controller)
        plan.items.removeAll { $0.file.components.first != top }
        plan.folders.removeAll { $0.path.first != top }
        #expect(plan.folders.map { $0.path.joined(separator: "/") } == [top, "\(top)/Sub"])
        #expect(plan.items.map(\.name).sorted() == ["One", "Three", "Two"], "the placeholder counts, the text file does not")

        let outcome = await controller.apply(plan)
        #expect(outcome == .synced(added: 3, folders: 2, moved: 0, trashed: 0))

        let library = root.itemController
        let topId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top], isFolder: true)
        let subId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Sub"], isFolder: true)
        let oneId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Sub", "One.png"], isFolder: false)
        let one = try #require(library.itemSync(for: oneId, noGame: true))
        #expect(one.name == "One")
        #expect(one.parentId == subId)
        #expect(one.category == .item)
        let oneFile = try #require(one.fileUrl)
        #expect(oneFile.location == .newCloud)
        let stored = try #require(files.storedLocation(of: oneFile))
        #expect(CloudDocumentController.canonicalPath(stored) == CloudDocumentController.canonicalPath(topUrl.appending(path: "Sub/One.png")))

        let topFolder = try #require(library.itemSync(for: topId, noGame: true))
        #expect(topFolder.isFolder)
        let twoId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Two.png"], isFolder: false)
        let threeId = CloudFolderScan.derivedId(module: NetworkModules.photo.token, path: [top, "Three.png"], isFolder: false)
        #expect(Set(topFolder.entries.map(\.childId)) == [subId, twoId, threeId], "the folder lists its sub folder and both files")
        #expect(topFolder.entries.count == 3)
        #expect(library.itemSync(for: subId, noGame: true)?.entries.map(\.childId) == [oneId])

        // What the other devices get: the rows in the store.
        let storage = DataController(context: store.context, token: NetworkModules.photo.token)
        let storedTop = try #require(try await storage.fetch(id: topId) as? PhotoModel)
        #expect(storedTop.entries.count == 3)
        let storedOne = try #require(try await storage.fetch(id: oneId) as? PhotoModel)
        #expect(storedOne.parentId == subId)

        // A second scan finds nothing of this test's, and applying the old plan again adds nothing.
        let rescan = try await scannedPlan(controller)
        #expect(!rescan.items.contains { $0.file.components.first == top })
        #expect(!rescan.folders.contains { $0.path.first == top })
        #expect(await controller.apply(plan) == .synced(added: 0, folders: 0, moved: 0, trashed: 0))
        #expect(library.itemDataModel.items.filter { library.itemSync(for: $0, noGame: true)?.name == "One" }.count == 1)
    }

    private func scannedPlan(_ controller: CloudScanController) async throws -> CloudScanPlan {
        guard case .plan(let plan) = try #require(await controller.scan()) else {
            Issue.record("the module folder should be readable")
            return CloudScanPlan()
        }
        return plan
    }

    @Test("The iCloud sync follows a file moved on iCloud, moves an item to the folder of its file and trashes an item whose file is gone")
    func cloudFolderSyncMovesAndTrashes() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let files = try #require(root.itemController.fileUrlDataController)
        let module = NetworkModules.photo.token
        let top = "SyncTest-\(UUID().uuidString)"
        let topUrl = files.cloudDocumentController.moduleUrl.appending(path: top, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: topUrl) }
        func write(_ path: String) throws {
            let url = topUrl.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        for path in ["Old/Moved.png", "Old/Gone.png", "Old/Stay.png"] { try write(path) }
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)
        var first = try await scannedPlan(controller)
        first.items.removeAll { $0.file.components.first != top }
        first.folders.removeAll { $0.path.first != top }
        #expect(await controller.apply(first) == .synced(added: 3, folders: 2, moved: 0, trashed: 0))

        func id(_ path: [String], folder: Bool = false) -> UUID {
            CloudFolderScan.derivedId(module: module, path: [top] + path, isFolder: folder)
        }
        let oldId = id(["Old"], folder: true)
        let movedId = id(["Old", "Moved.png"]), goneId = id(["Old", "Gone.png"]), stayId = id(["Old", "Stay.png"])
        let library = root.itemController

        // On iCloud: one file goes to a new folder, one is deleted. In the app: one item is taken
        // out of the folder of its file.
        try FileManager.default.createDirectory(at: topUrl.appending(path: "New"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: topUrl.appending(path: "Old/Moved.png"), to: topUrl.appending(path: "New/Moved.png"))
        try FileManager.default.removeItem(at: topUrl.appending(path: "Old/Gone.png"))
        let strayId = await library.addNew(type: .folder)
        root.editController.reset(name: "Stray", itemId: strayId)
        let stay = try #require(library.itemSync(for: stayId, noGame: true))
        stay.parentId = strayId
        root.editController.repairFolders(itemIds: [stayId])

        var plan = try await scannedPlan(controller)
        plan.items.removeAll { $0.file.components.first != top }
        plan.folders.removeAll { $0.path.first != top }
        plan.moves.removeAll { !($0.file?.components.first == top || $0.from.first == "Stray" || $0.to.first == top) }
        plan.removals.removeAll { $0.path.first != top }
        #expect(plan.items.isEmpty, "no file without an item")
        #expect(plan.removals.map(\.id) == [goneId])
        #expect(plan.movedFiles.map(\.id) == [movedId])
        #expect(plan.movedItems.map(\.id) == [stayId])
        #expect(plan.folders.map { $0.path.joined(separator: "/") } == ["\(top)/New"])

        // The user keeps the Gone item.
        let kept = plan.restricted(toDeselected: [goneId])
        #expect(kept.removals.isEmpty)

        let outcome = await controller.apply(plan)
        #expect(outcome == .synced(added: 0, folders: 1, moved: 2, trashed: 1))

        let newId = id(["New"], folder: true)
        let moved = try #require(library.itemSync(for: movedId, noGame: true))
        #expect(moved.parentId == newId)
        let movedFile = try #require(moved.fileUrl)
        #expect(CloudDocumentController.canonicalPath(try #require(files.storedLocation(of: movedFile)))
                == CloudDocumentController.canonicalPath(topUrl.appending(path: "New/Moved.png")))
        #expect(FileManager.default.fileExists(atPath: topUrl.appending(path: "New/Moved.png").path(percentEncoded: false)))
        #expect(library.itemSync(for: newId, noGame: true)?.entries.map(\.childId) == [movedId])
        #expect(library.itemSync(for: oldId, noGame: true)?.entries.map(\.childId).contains(movedId) == false, "the old folder no longer lists it")

        let stayed = try #require(library.itemSync(for: stayId, noGame: true))
        #expect(stayed.parentId == oldId)
        #expect(library.itemSync(for: strayId, noGame: true)?.entries.isEmpty == true)
        #expect(stayed.fileUrl?.rawUrl.lastPathComponent == "Stay.png", "the file keeps its name: only the item moved")
        #expect(FileManager.default.fileExists(atPath: topUrl.appending(path: "Old/Stay.png").path(percentEncoded: false)))

        #expect(library.itemSync(for: goneId, noGame: true)?.displayState == DisplayStateMask.totalHidden.rawValue, "trashed, not deleted")

        // The store has the same.
        let storage = DataController(context: store.context, token: module)
        let storedMoved = try #require(try await storage.fetch(id: movedId) as? PhotoModel)
        #expect(storedMoved.parentId == newId)
        #expect(storedMoved.fileUrl?.rawUrl.path(percentEncoded: false) == "/\(top)/New/Moved.png")

        // Nothing differs afterwards, apart from the trashed item that still references its file.
        var rescan = try await scannedPlan(controller)
        rescan.moves.removeAll { !($0.file?.components.first == top || $0.to.first == top) }
        rescan.items.removeAll { $0.file.components.first != top }
        #expect(rescan.moves.isEmpty && rescan.items.isEmpty)
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

extension PhotoRootModel {
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

struct InMemoryStore {
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
