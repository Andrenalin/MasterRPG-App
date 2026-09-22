// @copyright André Trettin

@preconcurrency import CoreData
import os.log

public enum CoreDataInitError: Equatable, Sendable {
    case none
    case loadModel
    case removeFile(message: String)
    case migration(message: String)
    case creation(message: String)
}

public extension CoreDataInitError {
    /// Classifies a failed `loadPersistentStores`. Only errors that say the store itself is
    /// unreadable (corruption, failed migration) are offered the destructive "delete the
    /// database" recovery; a disk-full, permission, locked or busy failure is transient and a
    /// healthy database must survive it. See CODE_AUDIT_15 §5.4.
    static func loadFailure(_ error: NSError) -> CoreDataInitError {
        let errors = [error] + ((error.userInfo[NSUnderlyingErrorKey] as? NSError).map { [$0] } ?? [])
        let transientCocoaCodes: Set<Int> = [
            NSFileWriteOutOfSpaceError, NSFileReadNoPermissionError, NSFileWriteNoPermissionError,
            NSFileLockingError, NSFileWriteVolumeReadOnlyError
        ]
        // SQLITE_BUSY, LOCKED, READONLY, IOERR, FULL, CANTOPEN, PROTOCOL
        let transientSQLiteCodes: Set<Int> = [5, 6, 8, 10, 13, 14, 15]
        let isTransient = errors.contains { candidate in
            switch candidate.domain {
            case NSCocoaErrorDomain: transientCocoaCodes.contains(candidate.code)
            case "NSSQLiteErrorDomain": transientSQLiteCodes.contains(candidate.code)
            default: false
            }
        }
        return isTransient ? .creation(message: error.localizedDescription) : .migration(message: error.localizedDescription)
    }
}

extension NSPersistentContainer {
    /// Removes the store's SQLite file together with its `-wal`/`-shm` sidecars. Deleting
    /// only the main file leaves a stale write-ahead log that SQLite can replay into the
    /// fresh store created next. See CODE_AUDIT_15 §5.4.
    func destroyStoreFiles(at url: URL) throws {
        try? persistentStoreCoordinator.destroyPersistentStore(at: url, type: .sqlite, options: nil)
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: url.path(percentEncoded: false) + suffix)
            guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            try fileManager.removeItem(at: file)
        }
    }
}

public enum CloudKitSyncState: Sendable, Equatable {
    case notStarted
    case inProgress
    case succeeded
    case failed(String)
}

@MainActor @Observable
public final class CoreDataInitModel {
    nonisolated init(inMemory: Bool, currentActor: AppPersistentActor) {
        self.inMemory = inMemory
        self.currentActor = currentActor
    }

    let inMemory: Bool
    let currentActor: AppPersistentActor
    var isInitialized = false

    var containerStoreUrl: URL?

    public internal(set) var context: NSManagedObjectContext?
    public internal(set) var container: NSPersistentContainer?
    public internal(set) var error: CoreDataInitError = .none

    public internal(set) var privatePersistentStore: NSPersistentStore?

    public internal(set) var spotlightIndexer: RpgSpotlightIndexerDelegate?
    var persistentHistoryTracker: PersistentHistoryTrackerManager?
    var persistentHistoryCleaner: PersistentHistoryCleaner?
    var cleanupTask: Task<Void, Never>?
    var cloudKitEventMonitoringTask: Task<Void, Never>?

    // CloudKit sync state for UI
    public var cloudKitSyncState: CloudKitSyncState = .notStarted
    public var lastSuccessfulSync: Date?

    public var hasError: Bool {
        error != .none
    }
    public var recoverableError: Bool {
        switch error {
        case .migration(_):
            return true
        default:
            return false
        }
    }

    /// Cancels this model's long-lived monitoring tasks. Call before dropping the
    /// reference to this model (e.g. a store swap in `DataBaseModel.setup()`), so
    /// the old `NSPersistentCloudKitContainer` and its never-finishing
    /// `eventChangedNotification` sequence don't outlive the controller for the
    /// rest of the process. See CODE_AUDIT_17 §3.9.
    public func stop() {
        cleanupTask?.cancel()
        cleanupTask = nil
        cloudKitEventMonitoringTask?.cancel()
        cloudKitEventMonitoringTask = nil
    }
}

public struct CoreDataPersistenceController {
    public init(inMemory: Bool = false, currentActor: AppPersistentActor) {
        model = CoreDataInitModel(inMemory: inMemory, currentActor: currentActor)
    }

    public let model: CoreDataInitModel

    @MainActor
    public func loadDatabase(bundles: [Bundle]) {
        guard !model.isInitialized else { return }

        model.isInitialized = true
        
#if !os(tvOS)
        // init path to stores
        guard let groupURL = FileManager.groupURL else {
            Logger.persistenceController.error("PersistenceController #\(#function) App Group container is unavailable")
            model.error = .loadModel
            return
        }
        let storeFolderURL = groupURL.appending(path: "Stores")
        let localFolderURL = storeFolderURL.appending(path: "Local")
        
        let fileManager = FileManager.default
        for folderURL in [localFolderURL] where !fileManager.fileExists(atPath: folderURL.path) {
            do {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.persistenceController.error("PersistenceController #\(#function) Failed to create the store folder: \(error.localizedDescription, privacy: .public)")
                model.error = .loadModel
            }
        }
#endif
                
        // Load Models - use provided bundles (no expensive enumeration or Info.plist parsing)
        guard let models = NSManagedObjectModel.mergedModel(from: bundles) else {
            model.error = .loadModel
            return
        }
        
        // private store setup
        let container = RPGPersistentContainer(name: "MasterRPGLocal", managedObjectModel: models)
        guard let localDescription = container.persistentStoreDescriptions.first else {
            model.error = .loadModel
            return
        }
#if !os(tvOS)
        localDescription.url = localFolderURL.appending(path: "local.sqlite")
#endif
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true
        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        model.container = container
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(filePath: "/dev/null")
        }

#if !os(tvOS)
        model.spotlightIndexer = RpgSpotlightIndexerDelegate(forStoreWith: localDescription, coordinator: container.persistentStoreCoordinator)
#endif
        
        // `loadPersistentStores` is documented as always asynchronous with no
        // guaranteed completion thread, so the store-dependent state below is set
        // from inside the completion handler rather than read immediately after the
        // (non-blocking) call returns — see `runOnMainActor` for how that stays safe
        // without breaking callers that rely on the (common, synchronous) fast path.
        let model = model
        container.loadPersistentStores { storeDescription, error in
            let initError: CoreDataInitError
            let storeUrl: URL?
            if let error = error as NSError?, let url = storeDescription.url {
                initError = .loadFailure(error)
                storeUrl = initError == .creation(message: error.localizedDescription) ? nil : url
            } else {
                initError = .none
                storeUrl = nil
            }
            runOnMainActor {
                model.containerStoreUrl = storeUrl
                model.error = initError
                Self.setupContext(container: container, model: model)
            }
        }
    }

    @MainActor
    public func recoverFromError() {
        guard model.recoverableError, let url = model.containerStoreUrl, let container = model.container else { return }
        do {
            try container.destroyStoreFiles(at: url)
            let model = model
            container.loadPersistentStores { _, error in
                let newError: CoreDataInitError = if let error = error as NSError? {
                    .creation(message: error.localizedDescription)
                } else {
                    .none
                }
                runOnMainActor {
                    model.error = newError
                    Self.setupContext(container: container, model: model)
                }
            }
        } catch {
            model.error = .removeFile(message: error.localizedDescription)
        }
    }

    @MainActor
    private static func setupContext(container: NSPersistentContainer, model: CoreDataInitModel) {
        guard model.error == .none else { return }
        // Setup main background context for regular operations
        let context = container.newBackgroundContext()
        context.name = "background_context"
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = model.currentActor.rawValue
        context.automaticallyMergesChangesFromParent = true
        model.context = context

#if !os(tvOS)
        model.spotlightIndexer?.startSpotlightIndexing()
#endif
        model.persistentHistoryTracker = PersistentHistoryTrackerManager(container: container, currentActor: model.currentActor, viewBackupContext: model.context)

        // Setup persistent history cleaner and run initial cleanup
        model.persistentHistoryCleaner = PersistentHistoryCleaner(container: container)

        model.cleanupTask?.cancel()
        model.cleanupTask = PersistentHistoryCleaner.scheduleRecurringCleanup { [weak model] in
            model?.persistentHistoryCleaner?.clean()
        }
    }
}

// @unchecked Sendable: a bare, stateless subclass of Apple's
// `NSPersistentContainer` — it adds no stored properties of its own, so there
// is nothing here for the compiler to actually race on; the annotation only
// bypasses `NSPersistentContainer` itself predating `Sendable`.
final class RPGPersistentContainer: NSPersistentContainer, @unchecked Sendable {}

/// Runs `work` on the main actor. `loadPersistentStores`'s completion handler is
/// documented as not guaranteed to run on any particular thread — but in practice,
/// for a healthy local (or already-cached CloudKit) store it fires synchronously on
/// the calling (main) thread. `DataBaseModel.setup()`/`ShareExtensionDatabaseService.setup()`
/// call `loadDatabase(bundles:)` and read `model.context`/`model.error` immediately
/// afterward with no `await`, relying on exactly that fast path. Running synchronously
/// via `MainActor.assumeIsolated` when we're already on the main thread preserves that
/// behavior; hopping through a `Task` only when the completion genuinely lands off-thread
/// (or later) keeps the rare slow path correct without breaking the common one.
func runOnMainActor(_ work: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(work)
    } else {
        Task { @MainActor in work() }
    }
}
