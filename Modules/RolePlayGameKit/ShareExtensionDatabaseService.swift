// @copyright André Trettin

import CoreRPG
import CoreData
import os.log

// Import necessary module bundles
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

/// Lightweight database service specifically for the Share Extension
/// Only loads necessary modules and skips advanced features like Spotlight indexing
@MainActor
public final class ShareExtensionDatabaseService {
    
    // MARK: - Properties
    
    public private(set) var context: NSManagedObjectContext?
    public private(set) var container: NSPersistentContainer?
    public private(set) var isReady = false
    
    private let useCloudKit: Bool
    private var persistence: CoreDataPersistenceController?
    
    // MARK: - Initialization
    
    public init(useCloudKit: Bool = false) {
        self.useCloudKit = useCloudKit
    }
    
    // MARK: - Setup
    
    /// Loads only the necessary modules for the share extension
    /// - Parameter modules: The specific modules needed (defaults to core modules)
    public func setup(for modules: [NetworkModules] = [.photo, .pdf, .audio]) async throws {
        guard !isReady else { return }
        
        // Only load bundles for modules we actually need
        let bundles = moduleBundles(for: modules)
        
        // Create lightweight persistence controller
        persistence = CoreDataPersistenceController(
            inMemory: false,
            currentActor: .sharingExtension
        )
        
        // Load with minimal configuration
        persistence?.loadDatabase(bundles: bundles)
        
        // Wait for context to be available
        guard let model = persistence?.model else {
            throw ShareExtensionError.databaseInitializationFailed
        }
        
        // Check for errors
        if model.error != .none {
            throw ShareExtensionError.databaseError(model.error)
        }
        
        // Set context
        self.context = model.context
        self.container = model.container
        self.isReady = true
    }
    
    // MARK: - Module Management
    
    private func moduleBundles(for modules: [NetworkModules]) -> [Bundle] {
        var bundles = [CoreRPG.Resources.bundle] // Always need core
        
        for module in modules {
            bundles.append(module.resourceBundle)
        }
        
        return bundles
    }
    
    // MARK: - Save Operations
    
    /// Performs a save operation with proper error handling
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

// MARK: - Supporting Types

extension NetworkModules {
    var resourceBundle: Bundle {
        switch self {
        case .photo: return PhotoRPG.Resources.bundle
        case .pdf: return PdfRPG.Resources.bundle
        case .audio: return AudioRPG.Resources.bundle
        case .adventure: return AdventureRPG.Resources.bundle
        case .dice: return DiceRPG.Resources.bundle
        case .table: return TableRPG.Resources.bundle
        case .map: return MapRPG.Resources.bundle
        case .value: return CharacterRPG.Resources.bundle
        case .weather: return WeatherRPG.Resources.bundle
        case .space: return SpaceRPG.Resources.bundle
        default: return CoreRPG.Resources.bundle
        }
    }
}

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
