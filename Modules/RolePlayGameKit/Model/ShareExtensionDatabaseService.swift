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
    public private(set) var batchContext: NSManagedObjectContext?
    public private(set) var container: NSPersistentContainer?
    public private(set) var isReady = false
        
    private let useCloudKit: Bool
    private var persistence: CoreDataPersistenceController?
    
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

        // Create persistence controller
        persistence = CoreDataPersistenceController(
            inMemory: false,
            currentActor: .sharingExtension
        )
        
        // Load complete database
        persistence?.loadDatabase(bundles: bundles)
        
        // Wait for context to be available
        guard let model = persistence?.model else {
            throw ShareExtensionError.databaseInitializationFailed
        }
        
        // Check for errors
        if model.error != .none {
            throw ShareExtensionError.databaseError(model.error)
        }
        
        // Set contexts
        self.context = model.context
        self.batchContext = model.batchContext
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
        }
    }
}
