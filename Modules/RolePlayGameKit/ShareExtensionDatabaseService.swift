// @copyright André Trettin

import CoreRPG
import CoreData
import os.log

// Import ALL module bundles - we need the complete database for proper saving
import PhotoRPG
import PdfRPG
import AudioRPG
import AdventureRPG
import DiceRPG
import TableRPG
import MapRPG
import CharacterRPG
import WeatherRPG
import SpaceRPG
import GameRPG

#if !os(tvOS)
import GeneratorRPG
#endif

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
    
    // Lightweight data controllers - minimal overhead for share extension
//    public private(set) var photoDataController: LightDataController?
//    public private(set) var mapDataController: LightDataController?
//    public private(set) var adventureDataController: LightDataController?
//    public private(set) var weatherDataController: LightDataController?
//    public private(set) var characterDataController: LightDataController?
    
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
        let bundles = allModuleBundles()
        
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
        
        // Initialize lightweight data controllers
        try await setupDataControllers()
        
        self.isReady = true
    }
    
    // MARK: - Data Controller Setup
    
    private func setupDataControllers() async throws {
        guard let context else {
            throw ShareExtensionError.contextNotAvailable
        }
        
        // Create lightweight data controllers for each module
        // These only handle Core Data operations without the full root model infrastructure
//        photoDataController = LightDataController(context: context, module: .photo)
//        mapDataController = LightDataController(context: context, module: .map)
//        adventureDataController = LightDataController(context: context, module: .adventure)
//        weatherDataController = LightDataController(context: context, module: .weather)
//        characterDataController = LightDataController(context: context, module: .value)
    }
    
    // MARK: - Module Management
    
    private func allModuleBundles() -> [Bundle] {
        var bundles = [
            CoreRPG.Resources.bundle,
            PhotoRPG.Resources.bundle,
            PdfRPG.Resources.bundle,
            AudioRPG.Resources.bundle,
            AdventureRPG.Resources.bundle,
            DiceRPG.Resources.bundle,
            TableRPG.Resources.bundle,
            MapRPG.Resources.bundle,
            CharacterRPG.Resources.bundle,
            WeatherRPG.Resources.bundle,
            SpaceRPG.Resources.bundle,
            GameRPG.Resources.bundle
        ]
        
        #if !os(tvOS)
        bundles.append(GeneratorRPG.Resources.bundle)
        #endif
        
        return bundles
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
            return "Failed to initialize database for share extension"
        case .databaseError(let error):
            return "Database error: \(error)"
        case .contextNotAvailable:
            return "Database context is not available"
        case .moduleNotSupported:
            return "The selected module is not supported in the share extension"
        }
    }
}
