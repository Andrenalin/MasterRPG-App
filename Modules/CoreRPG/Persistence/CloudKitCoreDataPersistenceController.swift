// @copyright André Trettin

import CoreData
import CloudKit
import Foundation
import os.log

public struct CloudKitCoreDataPersistenceController {
    static let cloudKitContainerIdentifier = FileManager.cloudContainerIdentifier

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
        guard let groupURL = FileManager.groupURL else {
            Logger.persistenceController.error("PersistenceController #\(#function) App Group container is unavailable")
            model.error = .loadModel
            return
        }
        let storeFolderURL = groupURL.appending(path: "Stores")
        let privateStoreFolderURL = storeFolderURL.appending(path: "Private")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: privateStoreFolderURL.path(percentEncoded: false)) {
            do {
                try fileManager.createDirectory(at: privateStoreFolderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.persistenceController.error("PersistenceController #\(#function) Failed to create the store folder: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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
        privateDescription.url = privateStoreFolderURL.appending(path: "private.sqlite")
        privateDescription.shouldMigrateStoreAutomatically = true
        privateDescription.shouldInferMappingModelAutomatically = true

        if Self.allowCloudKitSync && !model.inMemory {
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitCoreDataPersistenceController.cloudKitContainerIdentifier)
            cloudKitContainerOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = cloudKitContainerOptions
        }
        
        model.container = container
        DuplicateRowOrder.register(container)
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(filePath: "/dev/null")
        }
        
#if !os(tvOS)
        if Self.allowCloudKitSync {
            model.spotlightIndexer = RpgSpotlightIndexerDelegate(forStoreWith: privateDescription, coordinator: container.persistentStoreCoordinator)
        }
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
            var privateStore: NSPersistentStore?
            if let error = error as NSError?, let url = storeDescription.url {
                initError = .loadFailure(error)
                storeUrl = initError == .creation(message: error.localizedDescription) ? nil : url
            } else {
                initError = .none
                storeUrl = nil
                // Always capture the private store reference
                if let url = storeDescription.url {
                    privateStore = container.persistentStoreCoordinator.persistentStore(for: url)
                }
            }
            runOnMainActor {
                model.containerStoreUrl = storeUrl
                model.privatePersistentStore = privateStore
                model.error = initError

                // `InitializeCloudKitSchema` is a manual, local-only developer escape hatch —
                // it is never defined by any scheme or .xcconfig, so the branch below never
                // compiles into a shipped or CI build (see CODE_AUDIT §9.8). To push this
                // model's schema to the CloudKit *development* environment after a Core Data
                // model change, temporarily add `InitializeCloudKitSchema` to this target's
                // `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (or pass `-D InitializeCloudKitSchema`
                // to `xcodebuild`), run the app once, then remove the flag again — per Apple's
                // documented one-off `NSPersistentCloudKitContainer.initializeCloudKitSchema()`
                // workflow. Never leave the flag enabled: it skips `setupContext`, so the app
                // never finishes its normal Core Data setup while it's on.
#if InitializeCloudKitSchema
                do {
                    try container.initializeCloudKitSchema()
                } catch {
                    Logger.persistenceController.error("\(#function): initializeCloudKitSchema failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                }
                Logger.persistenceController.info("initializeCloudKitSchema succeeded")
#else
                Self.setupContext(container: container, model: model)
#endif
            }
        }
    }

    @MainActor
    public func recoverFromError() {
        model.recoverStore { container, model in
            Self.setupContext(container: container, model: model)
        }
    }

    @MainActor
    private static func setupContext(container: NSPersistentContainer, model: CoreDataInitModel) {
        // Setup main background context for regular operations
        guard model.installBackgroundContext(from: container) else { return }

#if !os(tvOS)
        if let spotlightIndexer = model.spotlightIndexer {
            Task { await spotlightIndexer.startIndexing() }
        }
#endif

        // Setup CloudKit event monitoring if sync is enabled
        if allowCloudKitSync && !model.inMemory {
            Self.setupCloudKitEventMonitoring(container: container, model: model)
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
            localModel.cleanupTask = PersistentHistoryCleaner.scheduleRecurringCleanup { [weak localModel] in
                await localModel?.persistentHistoryCleaner?.clean()
            }
        }
    }

    @MainActor
    private static func setupCloudKitEventMonitoring(container: NSPersistentContainer, model: CoreDataInitModel) {
        model.cloudKitEventMonitoringTask?.cancel()
        model.cloudKitEventMonitoringTask = Task { [weak model] in
            let events = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification,
                object: container
            )
            for await notification in events {
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    continue
                }

                guard let model else { return }
                model.apply(CloudKitSyncEvent(event).modelUpdate())
            }
        }
    }

    private static let allowCloudKitSync: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(where: { $0 == "-allowCloudKitSync" }), index + 1 < arguments.count else { return true }
        return arguments[index + 1] == "1"
    }()
}

// `NSPersistentCloudKitContainer` is `@unchecked Sendable` in the SDK, and Swift requires a
// subclass to restate that inherited conformance. This subclass adds no stored state.
// See CODE_AUDIT_18 §3.18.
final class RPGPersistentCloudKitContainer: NSPersistentCloudKitContainer, @unchecked Sendable {}
