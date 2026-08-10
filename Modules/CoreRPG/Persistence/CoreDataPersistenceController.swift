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

public enum CloudKitSyncState: Sendable, Equatable {
    case notStarted
    case inProgress
    case succeeded
    case failed(String)
}

@MainActor @Observable
public final class CoreDataInitModel: @unchecked Sendable {
    nonisolated init(inMemory: Bool, currentActor: AppPersistentActor) {
        self.inMemory = inMemory
        self.currentActor = currentActor
    }

    let inMemory: Bool
    let currentActor: AppPersistentActor
    var isInitialized = false

    var containerStoreUrl: URL?

    public internal(set) var context: NSManagedObjectContext?
    public internal(set) var batchContext: NSManagedObjectContext?
    public internal(set) var container: NSPersistentContainer?
    public internal(set) var error: CoreDataInitError = .none

    public internal(set) var privatePersistentStore: NSPersistentStore?

    public internal(set) var spotlightIndexer: RpgSpotlightIndexerDelegate?
    var persistentHistoryTracker: PersistentHistoryTrackerManager?
    var persistentHistoryCleaner: PersistentHistoryCleaner?
    var cleanupTask: Task<Void, Never>?

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

    public var isSyncing: Bool {
        if case .inProgress = cloudKitSyncState {
            return true
        }
        return false
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
        let groupURL = FileManager.groupURL
        let storeFolderURL = groupURL.appendingPathComponent("Stores")
        let localFolderURL = storeFolderURL.appendingPathComponent("Local")
        
        let fileManager = FileManager.default
        for folderURL in [localFolderURL] where !fileManager.fileExists(atPath: folderURL.path) {
            do {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.persistenceController.error("PersistenceController #\(#function) Failed to create the store folder: \(error.localizedDescription)")
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
        localDescription.url = localFolderURL.appendingPathComponent("local.sqlite")
#endif
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true
        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        model.container = container
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
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
                initError = .migration(message: error.localizedDescription)
                storeUrl = url
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
            try FileManager.default.removeItem(at: url)
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

        // Setup dedicated batch context for batch operations
        let batchContext = container.newBackgroundContext()
        batchContext.name = "batchContext"
        batchContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        batchContext.transactionAuthor = model.currentActor.rawValue
        batchContext.automaticallyMergesChangesFromParent = true
        model.batchContext = batchContext

#if !os(tvOS)
        model.spotlightIndexer?.startSpotlightIndexing()
#endif
        model.persistentHistoryTracker = PersistentHistoryTrackerManager(container: container, currentActor: model.currentActor, viewBackupContext: model.context)

        // Setup persistent history cleaner and run initial cleanup
        model.persistentHistoryCleaner = PersistentHistoryCleaner(container: container)

        model.cleanupTask?.cancel()
        model.cleanupTask = Task { [weak model] in
            try? await Task.sleep(for: .seconds(5))
            model?.persistentHistoryCleaner?.clean()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
                model?.persistentHistoryCleaner?.clean()
            }
        }
    }
}

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
