// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation
import os.log

/// Database service for the Share Extension
/// Loads the FULL database (all modules) to prevent Core Data corruption
/// Uses lightweight data controllers instead of full root models
@MainActor
public final class ShareExtensionDatabaseService {
    
    // MARK: - Properties
    
    public private(set) var context: NSManagedObjectContext?
    public private(set) var container: NSPersistentContainer?
    public private(set) var isReady = false

    private let useCloudKit: Bool
    // Holds whichever controller `setup()` actually constructs, so `save()`'s error path
    // and any future re-setup stay agnostic to which one is live.
    private var localPersistence: CoreDataPersistenceController?
    private var cloudPersistence: CloudKitCoreDataPersistenceController?

    // MARK: - Initialization

    public init(useCloudKit: Bool = false) {
        self.useCloudKit = useCloudKit
    }

    // MARK: - Setup

    /// Loads ALL modules to ensure database integrity
    /// Loading partial modules can corrupt the Core Data store
    public func setup() async throws {
        guard !isReady else { return }

        // Load ALL module bundles
        let bundles = DataBaseModel.rpgModuleBundles

        // Must open the SAME store the main app is currently using — the CloudKit-synced
        // private store when the user has iCloud sync on, the local-only store otherwise.
        // This used to always construct `CoreDataPersistenceController` regardless of
        // `useCloudKit`, so anything shared while the main app was in CloudKit mode was
        // written to a SQLite file the main app never opens and silently lost. See
        // CODE_AUDIT §5.1.
        let model: CoreDataInitModel
        if useCloudKit {
            let persistence = CloudKitCoreDataPersistenceController(
                inMemory: false,
                currentActor: .sharingExtension
            )
            cloudPersistence = persistence
            persistence.loadDatabase(bundles: bundles)
            model = persistence.model
        } else {
            let persistence = CoreDataPersistenceController(
                inMemory: false,
                currentActor: .sharingExtension
            )
            localPersistence = persistence
            persistence.loadDatabase(bundles: bundles)
            model = persistence.model
        }

        // Check for errors
        if model.error != .none {
            throw ShareExtensionError.databaseError(model.error)
        }

        // Set contexts
        self.context = model.context
        self.container = model.container

        self.isReady = true
    }
    
    
    // MARK: - Save Operations
    
    /// Saves all changes to Core Data
    public func save() async throws {
        guard let context else {
            throw ShareExtensionError.contextNotAvailable
        }
        
        try await context.perform {
            guard context.hasChanges else { return }
            try context.save()
        }
    }
}

// MARK: - Error Types

public enum ShareExtensionError: LocalizedError {
    case databaseInitializationFailed
    case databaseError(CoreDataInitError)
    case contextNotAvailable
    case moduleNotSupported
    /// Photo was chosen but nothing shared could be read as a photo.
    case noPhotoToSave
    
    public var errorDescription: String? {
        switch self {
        case .databaseInitializationFailed:
            return String(
                localized: "Failed to initialize the database for the share extension.",
                bundle: .module
            )
        case .databaseError(let error):
            return String(
                localized: "Database error: \(String(describing: error))",
                bundle: .module
            )
        case .contextNotAvailable:
            return String(
                localized: "The database context is not available.",
                bundle: .module
            )
        case .moduleNotSupported:
            return String(
                localized: "The selected module is not supported in the share extension.",
                bundle: .module
            )
        case .noPhotoToSave:
            return String(
                localized: "There is no photo to save. Choose another module to save the text.",
                bundle: .module
            )
        }
    }

    /// Whether saving into `module` has anything to save. Saving to Photo with no image would
    /// otherwise close as if it worked and lose the shared text. See CODE_AUDIT_26 §5.47.
    public static func canSave(to module: NetworkModules, imageCount: Int) -> Bool {
        module != .photo || imageCount > 0
    }
}
