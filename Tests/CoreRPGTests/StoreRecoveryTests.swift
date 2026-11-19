// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.1: store recovery deletes the database files, so it is the one path
/// whose bug means local data loss. These tests run it against real SQLite files in a temporary
/// folder. `recoverStore` is shared code: the local and the CloudKit controller both call it, so
/// these tests cover the CloudKit store's recovery too (the CloudKit container itself needs an
/// iCloud account and is not created here).
@MainActor
@Suite("Store recovery")
struct StoreRecoveryTests {
    // MARK: - Fixtures

    /// A temporary folder that is removed (and made writable again) when the test ends.
    private final class Folder {
        let url: URL

        init() throws {
            url = URL.temporaryDirectory.appending(path: "StoreRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func file(_ name: String) -> URL { url.appending(path: name) }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: file(name).path(percentEncoded: false))
        }

        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: file(name))
        }

        deinit {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makeContainer(storeUrl: URL) throws -> NSPersistentContainer {
        let momd = try #require(CoreRPG.Resources.bundle.url(forResource: "Model", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: momd))
        let container = NSPersistentContainer(name: "StoreRecovery-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeUrl)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        return container
    }

    /// Loads `container` and returns the load error, if any.
    private func load(_ container: NSPersistentContainer) -> NSError? {
        var loadError: NSError?
        container.loadPersistentStores { _, error in loadError = error as NSError? }
        return loadError
    }

    /// A model whose store file is garbage, loaded the way `loadDatabase` does: the container, the
    /// store url and the classified error are recorded on the model.
    private func damagedModel(in folder: Folder) throws -> CoreDataInitModel {
        let storeUrl = folder.file("local.sqlite")
        try folder.write("local.sqlite", String(repeating: "not a sqlite database ", count: 200))
        let container = try makeContainer(storeUrl: storeUrl)
        let loadError = try #require(load(container), "a garbage file must not load")

        let model = CoreDataInitModel(inMemory: false, currentActor: .mainApp)
        model.container = container
        model.containerStoreUrl = storeUrl
        model.error = .loadFailure(loadError)
        return model
    }

    // MARK: - What counts as recoverable

    @Test("A store the engine cannot read is offered the recovery")
    func unreadableStoreIsRecoverable() throws {
        let folder = try Folder()
        let model = try damagedModel(in: folder)

        guard case .migration = model.error else {
            Issue.record("A garbage file must be classified as a migration failure, got \(model.error)")
            return
        }
        #expect(model.recoverableError)
        #expect(model.hasError)
    }

    @Test("Only a migration failure is recoverable", arguments: [
        CoreDataInitError.none,
        .loadModel,
        .removeFile(message: "x"),
        .creation(message: "x")
    ])
    func onlyMigrationIsRecoverable(error: CoreDataInitError) {
        let model = CoreDataInitModel(inMemory: false, currentActor: .mainApp)
        model.error = error

        #expect(!model.recoverableError)
    }

    @Test("A transient failure is a creation error that never offers the destructive recovery", arguments: [
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
        NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
        NSError(domain: NSCocoaErrorDomain, code: NSFileLockingError),
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError),
        NSError(domain: "NSSQLiteErrorDomain", code: 5),
        NSError(domain: "NSSQLiteErrorDomain", code: 13),
        // The transient cause sits one level down, under a generic Core Data error.
        NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOperationError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "NSSQLiteErrorDomain", code: 13)
        ])
    ])
    func transientFailureIsNotRecoverable(error: NSError) {
        let classified = CoreDataInitError.loadFailure(error)

        guard case .creation = classified else {
            Issue.record("\(error) must not offer the destructive recovery, got \(classified)")
            return
        }
        let model = CoreDataInitModel(inMemory: false, currentActor: .mainApp)
        model.error = classified
        #expect(!model.recoverableError)
    }

    @Test("A corruption or migration failure is classified as recoverable", arguments: [
        NSError(domain: "NSSQLiteErrorDomain", code: 11),
        NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError),
        NSError(domain: NSCocoaErrorDomain, code: NSMigrationError)
    ])
    func corruptionIsRecoverable(error: NSError) {
        guard case .migration = CoreDataInitError.loadFailure(error) else {
            Issue.record("\(error) is a damaged store and must be offered the recovery")
            return
        }
    }

    // MARK: - destroyStoreFiles

    @Test("Destroying a store removes the database with its -wal and -shm and nothing else")
    func destroyRemovesTheStoreFilesOnly() throws {
        let folder = try Folder()
        let storeUrl = folder.file("local.sqlite")
        for name in ["local.sqlite", "local.sqlite-wal", "local.sqlite-shm", "local.sqlite.bak", "other.sqlite", "notes.txt"] {
            try folder.write(name, "data")
        }
        let container = try makeContainer(storeUrl: storeUrl)

        try container.destroyStoreFiles(at: storeUrl)

        #expect(!folder.exists("local.sqlite"))
        #expect(!folder.exists("local.sqlite-wal"))
        #expect(!folder.exists("local.sqlite-shm"))
        // A neighbour that merely shares the prefix, and every other file, survive.
        #expect(folder.exists("local.sqlite.bak"))
        #expect(folder.exists("other.sqlite"))
        #expect(folder.exists("notes.txt"))
    }

    @Test("Destroying a store whose sidecars are missing succeeds")
    func destroyToleratesMissingSidecars() throws {
        let folder = try Folder()
        let storeUrl = folder.file("local.sqlite")
        try folder.write("local.sqlite", "data")
        let container = try makeContainer(storeUrl: storeUrl)

        try container.destroyStoreFiles(at: storeUrl)

        #expect(!folder.exists("local.sqlite"))
    }

    // MARK: - recoverStore

    @Test("A damaged store is replaced by a loadable empty one and the error clears")
    func damagedStoreIsReplacedByAnEmptyOne() async throws {
        // Given: a garbage database with a stale write-ahead log beside it.
        let folder = try Folder()
        let model = try damagedModel(in: folder)
        try folder.write("local.sqlite-wal", "stale log")
        try folder.write("local.sqlite-shm", "stale index")
        var setUpCount = 0

        // When
        model.recoverStore { container, model in
            setUpCount += 1
            _ = model.installBackgroundContext(from: container)
        }
        let recovered = await awaitCondition { model.error == .none && model.context != nil }

        // Then: the store loads, is empty, and the old files are gone.
        #expect(recovered, "the recovery did not finish, error: \(model.error)")
        #expect(setUpCount == 1)
        #expect(!model.recoverableError)
        let context = try #require(model.context)
        let rows = try await context.perform {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "TagDataModel"))
        }
        #expect(rows == 0)
        let staleLog = try? String(contentsOf: folder.file("local.sqlite-wal"), encoding: .utf8)
        #expect(staleLog != "stale log", "a stale write-ahead log must not be replayed into the fresh store")
    }

    @Test("The store that was recovered keeps what is saved to it afterwards")
    func recoveredStoreIsUsable() async throws {
        let folder = try Folder()
        let model = try damagedModel(in: folder)
        model.recoverStore { container, model in
            _ = model.installBackgroundContext(from: container)
        }
        #expect(await awaitCondition { model.context != nil })
        let context = try #require(model.context)

        try await context.perform {
            let tag = TagDataModel(context: context)
            tag.module = 3
            tag.title = "After recovery"
            tag.count = 1
            try context.save()
        }

        let count = try await context.perform {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "TagDataModel"))
        }
        #expect(count == 1)
    }

    @Test("A recovery that cannot delete the files surfaces removeFile and sets nothing up")
    func undeletableFilesSurfaceARemoveFileError() async throws {
        // Given: a damaged store in a folder that does not allow deleting.
        let folder = try Folder()
        let model = try damagedModel(in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))
        var setUpCount = 0

        // When
        model.recoverStore { _, _ in setUpCount += 1 }

        // Then
        guard case .removeFile = model.error else {
            Issue.record("Expected removeFile, got \(model.error)")
            return
        }
        #expect(setUpCount == 0)
        #expect(model.context == nil)
        #expect(folder.exists("local.sqlite"), "nothing may be removed when deletion is not allowed")
    }

    @Test("A non-recoverable error leaves the files untouched", arguments: [
        CoreDataInitError.creation(message: "disk full"),
        .loadModel,
        .none
    ])
    func nonRecoverableErrorTouchesNothing(error: CoreDataInitError) async throws {
        // Given: the files of a healthy-looking store and an error that is not a corruption.
        let folder = try Folder()
        let storeUrl = folder.file("local.sqlite")
        try folder.write("local.sqlite", "precious data")
        try folder.write("local.sqlite-wal", "precious log")
        let model = CoreDataInitModel(inMemory: false, currentActor: .mainApp)
        model.container = try makeContainer(storeUrl: storeUrl)
        model.containerStoreUrl = storeUrl
        model.error = error
        var setUpCount = 0

        // When
        model.recoverStore { _, _ in setUpCount += 1 }
        let changed = await conditionHolds(for: .milliseconds(50)) {
            model.error == error && setUpCount == 0
        }

        // Then
        #expect(changed, "the recovery must do nothing for \(error)")
        #expect(try String(contentsOf: storeUrl, encoding: .utf8) == "precious data")
        #expect(try String(contentsOf: folder.file("local.sqlite-wal"), encoding: .utf8) == "precious log")
    }

    @Test("A recoverable error without a recorded store url deletes nothing")
    func missingStoreUrlDeletesNothing() async throws {
        let folder = try Folder()
        try folder.write("local.sqlite", "precious data")
        let model = try damagedModel(in: folder)
        model.containerStoreUrl = nil
        var setUpCount = 0

        model.recoverStore { _, _ in setUpCount += 1 }

        #expect(setUpCount == 0)
        #expect(folder.exists("local.sqlite"))
    }

    // MARK: - In-memory configuration

    @Test("The in-memory configuration is not backed by a file and offers no recovery")
    func inMemoryStoreNeverTouchesTheDisk() throws {
        let controller = CoreDataPersistenceController(inMemory: true, currentActor: .mainApp)

        controller.loadDatabase(bundles: [CoreRPG.Resources.bundle])

        let container = try #require(controller.model.container)
        let url = try #require(container.persistentStoreDescriptions.first?.url)
        #expect(url == URL(filePath: "/dev/null"))
        // Loaded, so no error was recorded and no store url was kept for a recovery to delete.
        #expect(controller.model.error == .none)
        #expect(controller.model.containerStoreUrl == nil)
        controller.recoverFromError()
        #expect(controller.model.error == .none)
        controller.model.stop()
    }
}
#endif
