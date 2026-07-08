// @copyright André Trettin

@preconcurrency import CoreData
import CloudKit
import Foundation
import os.log

private enum CloudKitEventModelUpdate: Sendable {
    case none
    case syncState(CloudKitSyncState)
    case importSucceeded(Date)
    case exportSucceeded(Date)
}

public struct CloudKitCoreDataPersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.de.andretrettin.gamemaster"

    public init(inMemory: Bool = false, currentActor: AppPersistentActor) {
        model = CoreDataInitModel(inMemory: inMemory, currentActor: currentActor)
    }

    public let model: CoreDataInitModel

    @MainActor
    public func loadDatabase(bundles: [Bundle]) {
        guard !model.isInitialized else {
            return
        }

        model.isInitialized = true
        
        // init path to stores
        let groupURL = FileManager.groupURL
        let storeFolderURL = groupURL.appendingPathComponent("Stores")
        let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: privateStoreFolderURL.path) {
            do {
                try fileManager.createDirectory(at: privateStoreFolderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.persistenceController.error("PersistenceController #\(#function) Failed to create the store folder: \(error.localizedDescription)")
                model.error = .loadModel
            }
        }

        // Load Models - use provided bundles (no expensive enumeration or Info.plist parsing)
        guard let models = NSManagedObjectModel.mergedModel(from: bundles) else {
            model.error = .loadModel
            return
        }
        
        // private store setup
        let container = RPGPersistentCloudKitContainer(name: "MasterRPGCloudKit", managedObjectModel: models)

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            model.error = .loadModel
            return
        }
        privateDescription.url = privateStoreFolderURL.appendingPathComponent("private.sqlite")

        if allowCloudKitSync && !model.inMemory {
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitCoreDataPersistenceController.cloudKitContainerIdentifier)
            cloudKitContainerOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = cloudKitContainerOptions
        }
        
        model.container = container
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
#if !os(tvOS)
        if allowCloudKitSync {
            model.spotlightIndexer = RpgSpotlightIndexerDelegate(forStoreWith: privateDescription, coordinator: container.persistentStoreCoordinator)
        }
#endif
        
        var privateStore: NSPersistentStore?
        var storeUrl: URL? = nil
        var initError: CoreDataInitError = .none
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError?, let url = storeDescription.url {
                initError = .migration(message: error.localizedDescription)
                storeUrl = url
                return
            }
            // Always capture the private store reference
            if let url = storeDescription.url {
                privateStore = container.persistentStoreCoordinator.persistentStore(for: url)
            }
        }
        model.containerStoreUrl = storeUrl
        model.privatePersistentStore = privateStore
        model.error = initError

#if InitializeCloudKitSchema
        do {
            try container.initializeCloudKitSchema()
        } catch {
            print("\(#function): initializeCloudKitSchema: \(error)")
        }
        print("Successfull")
#else
        setupContext()
#endif        
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

            // Setup CloudKit event monitoring if sync is enabled
            if allowCloudKitSync && !model.inMemory {
                setupCloudKitEventMonitoring(container: container)
            }

            let currentActor = model.currentActor
            let localContext = model.context

            let localModel = model
            
            if allowCloudKitSync {
                let persistentHistoryTracker = PersistentHistoryTrackerManager(container: container, currentActor: currentActor, viewBackupContext: localContext)
                localModel.persistentHistoryTracker = persistentHistoryTracker
                
                // Setup persistent history cleaner and run initial cleanup
                localModel.persistentHistoryCleaner = PersistentHistoryCleaner(container: container)
                
                // Run cleanup on launch (after a delay to not block startup)
                localModel.cleanupTask?.cancel()
                localModel.cleanupTask = Task { [weak localModel] in
                    try? await Task.sleep(for: .seconds(5))
                    localModel?.persistentHistoryCleaner?.clean()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(24 * 60 * 60))
                        localModel?.persistentHistoryCleaner?.clean()
                    }
                }
            }
        }
    }

    @MainActor
    private func setupCloudKitEventMonitoring(container: NSPersistentContainer) {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak model] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            let update: CloudKitEventModelUpdate
            switch event.type {
            case .setup:
                if event.succeeded {
                    Logger.persistenceController.info("CloudKit setup succeeded")
                    update = .none
                } else {
                    Logger.persistenceController.info("CloudKit setup in progress")
                    update = .syncState(.inProgress)
                }

            case .import:
                if event.succeeded {
                    Logger.persistenceController.info("CloudKit import succeeded")
                    update = .importSucceeded(Date())
                } else if let error = event.error {
                    Logger.persistenceController.error("CloudKit import error: \(error.localizedDescription, privacy: .public)")
                    update = .syncState(.failed(error.localizedDescription))
                } else {
                    update = .syncState(.inProgress)
                }

            case .export:
                if event.succeeded {
                    Logger.persistenceController.info("CloudKit export succeeded")
                    update = .exportSucceeded(Date())
                } else if let error = event.error {
                    Logger.persistenceController.error("CloudKit export error: \(error.localizedDescription, privacy: .public)")
                    update = .none
                } else {
                    update = .none
                }

            @unknown default:
                Logger.persistenceController.debug("CloudKit unknown event type")
                update = .none
            }

            MainActor.assumeIsolated {
                guard let model = model else { return }

                switch update {
                case .none:
                    break
                case .syncState(let state):
                    model.cloudKitSyncState = state
                case .importSucceeded(let date):
                    model.cloudKitSyncState = .succeeded
                    model.lastSuccessfulSync = date
                case .exportSucceeded(let date):
                    model.lastSuccessfulSync = date
                }
            }
        }
    }
    
    private var allowCloudKitSync: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(where: { $0 == "-allowCloudKitSync" }), index + 1 < arguments.count else { return true }
        return arguments[index + 1] == "1"
    }()
}

final class RPGPersistentCloudKitContainer: NSPersistentCloudKitContainer, @unchecked Sendable {}
