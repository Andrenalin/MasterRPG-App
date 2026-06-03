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

@Observable
public final class CoreDataInitModel: @unchecked Sendable {
    init(inMemory: Bool, currentActor: AppPersistentActor) {
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
        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        model.container = container
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

#if !os(tvOS)
        model.spotlightIndexer = RpgSpotlightIndexerDelegate(forStoreWith: localDescription, coordinator: container.persistentStoreCoordinator)
#endif
        
        var storeUrl: URL? = nil
        var initError: CoreDataInitError = .none
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError?, let url = storeDescription.url {
                initError = .migration(message: error.localizedDescription)
                storeUrl = url
            }
        }
        model.containerStoreUrl = storeUrl
        model.error = initError
        
        setupContext()
    }
    
    @MainActor
    public func recoverFromError() {
        guard model.recoverableError, let url = model.containerStoreUrl, let container = model.container else { return }
        do {
            try FileManager.default.removeItem(at: url)
            var newError: CoreDataInitError = .none
            container.loadPersistentStores { _, error in
                if let error = error as NSError? {
                    newError = .creation(message: error.localizedDescription)
                }
            }
            model.error = newError
            setupContext()
        } catch {
            model.error = .removeFile(message: error.localizedDescription)
        }
    }
    
    @MainActor
    private func setupContext() {
        if let container = model.container, model.error == .none {
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
}

final class RPGPersistentContainer: NSPersistentContainer, @unchecked Sendable {}
