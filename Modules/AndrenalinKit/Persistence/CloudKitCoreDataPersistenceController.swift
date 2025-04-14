// @copyright André Trettin

@preconcurrency import CoreData
import CloudKit
import Foundation
import os.log

public struct CloudKitCoreDataPersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.de.andretrettin.gamemaster"
    
    public init(inMemory: Bool = false, currentActor: AppPersistentActor) {
        model = CoreDataInitModel(inMemory: inMemory, currentActor: currentActor)
    }
    
    public let model: CoreDataInitModel
    
    @MainActor
    public func loadDatabase() {
        guard !model.isInitialized else {
            return
        }
        
        model.isInitialized = true
        
        // init path to stores
        let groupURL = FileManager.groupURL
        let storeFolderURL = groupURL.appendingPathComponent("Stores")
        let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private")
        let sharedStoreFolderURL = storeFolderURL.appendingPathComponent("Shared")
        
        let fileManager = FileManager.default
        for folderURL in [privateStoreFolderURL, sharedStoreFolderURL] where !fileManager.fileExists(atPath: folderURL.path) {
            do {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.persistenceController.error("PersistenceController #\(#function) Failed to create the store folder: \(error.localizedDescription)")
                model.error = .loadModel
            }
        }

        // Load Models
#if os(macOS)
        let frameworks = Bundle.allFrameworks.filter { $0.bundleIdentifier?.hasPrefix("de.andretrettin") ?? false }
#else
        let frameworks = Bundle.allFrameworks.filter { $0.resourceURL?.lastPathComponent.hasPrefix("RPG") ?? false }
#endif
        
        var path = Bundle.main.paths(forResourcesOfType: "bundle", inDirectory: nil)
        if path.isEmpty {
            path = Bundle(for: RPGPersistentCloudKitContainer.self).paths(forResourcesOfType: "bundle", inDirectory: nil)
        }
        var bundles = path.compactMap { Bundle(path: $0) }
        bundles.append(Bundle.main)
        bundles.append(Bundle(for: RPGPersistentCloudKitContainer.self))
        bundles.append(contentsOf: frameworks)
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
        
        // don't set the configuration name - it will cause an error that the configuration cannot be found by core data. Before it was working for the cloud container. Might be that AppGroup changed this.
        //privateDescription.configuration = "Private"
        if allowCloudKitSync {
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitCoreDataPersistenceController.cloudKitContainerIdentifier)

        cloudKitContainerOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = cloudKitContainerOptions

        if !model.inMemory {
            // shared store setup
            guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription else {
                Logger.persistenceController.error("PersistenceController #\(#function) Copying the private store description returned an unexpected value.")
                model.error = .loadModel
                return
            }
            sharedDescription.url = sharedStoreFolderURL.appendingPathComponent("shared.sqlite")
            sharedDescription.configuration = "Shared"
            
            let sharedStoreOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitCoreDataPersistenceController.cloudKitContainerIdentifier)
            sharedStoreOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedStoreOptions
            
            // Shared DB is not used at the moment
            //container.persistentStoreDescriptions.append(sharedDescription)
        }
        
        model.container = container
        if model.inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
#if !os(tvOS)
        model.spotlightIndexer = RpgSpotlightIndexerDelegate(forStoreWith: privateDescription, coordinator: container.persistentStoreCoordinator)
#endif
        
        var privateStore: NSPersistentStore?
        var sharedStore: NSPersistentStore?
        var storeUrl: URL? = nil
        var initError: CoreDataInitError = .none
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError?, let url = storeDescription.url {
                initError = .migration(message: error.localizedDescription)
                storeUrl = url
                return
            }
            guard let cloudKitContainerOptions = storeDescription.cloudKitContainerOptions else {
                return
            }
            if cloudKitContainerOptions.databaseScope == .private {
                privateStore = container.persistentStoreCoordinator.persistentStore(for: storeDescription.url!)
            } else if cloudKitContainerOptions.databaseScope == .shared {
                sharedStore = container.persistentStoreCoordinator.persistentStore(for: storeDescription.url!)
            }
        }
        model.containerStoreUrl = storeUrl
        model.privatePersistentStore = privateStore
        model.sharedPersistentStore = sharedStore
        model.error = initError

#if InitializeCloudKitSchema
        do {
            try container.initializeCloudKitSchema()
        } catch {
            print("\(#function): initializeCloudKitSchema: \(error)")
        }
        print("Successfull")
#endif

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
            let context = container.newBackgroundContext()
            context.name = "view_background_context"
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.transactionAuthor = model.currentActor.rawValue
            context.automaticallyMergesChangesFromParent = true

            do {
                try context.performAndWait {
                    try context.setQueryGenerationFrom(.current)
                }
            } catch {
                Logger.persistenceController.error("Failed to pin viewContext to the current generation: \(error.localizedDescription, privacy: .public)")
            }
            model.context = context
#if !os(tvOS)
            model.spotlightIndexer?.startSpotlightIndexing()
#endif
            
            context.performAndWait {
                model.persistentHistoryTracker = PersistentHistoryTrackerManager(container: container, model: model)
            }
        }
    }
    
    private var allowCloudKitSync: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(where: { $0 == "-allowCloudKitSync" }), index + 1 < arguments.count - 1 else { return true }
        return arguments[index + 1] == "1"
    }()
}

final class RPGPersistentCloudKitContainer: NSPersistentCloudKitContainer, @unchecked Sendable {}
