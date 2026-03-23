// @copyright André Trettin

import CoreRPG
import CoreData
import CloudKit

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import GameRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG


@Observable
public final class DataBaseModel {

#if os(tvOS)
    public static let rpgModuleBundles: [Bundle] = [
        CoreRPG.Resources.bundle,
        AdventureRPG.Resources.bundle,
        AudioRPG.Resources.bundle,
        CharacterRPG.Resources.bundle,
        DiceRPG.Resources.bundle,
        GameRPG.Resources.bundle,
        MapRPG.Resources.bundle,
        PdfRPG.Resources.bundle,
        PhotoRPG.Resources.bundle,
        SpaceRPG.Resources.bundle,
        TableRPG.Resources.bundle,
        WeatherRPG.Resources.bundle
    ]
#else
    public static let rpgModuleBundles: [Bundle] = [
        CoreRPG.Resources.bundle,
        AdventureRPG.Resources.bundle,
        AudioRPG.Resources.bundle,
        CharacterRPG.Resources.bundle,
        DiceRPG.Resources.bundle,
        GameRPG.Resources.bundle,
        GeneratorRPG.Resources.bundle,
        MapRPG.Resources.bundle,
        PdfRPG.Resources.bundle,
        PhotoRPG.Resources.bundle,
        SpaceRPG.Resources.bundle,
        TableRPG.Resources.bundle,
        WeatherRPG.Resources.bundle
    ]
#endif

    public private(set) var context: NSManagedObjectContext?
    public private(set) var batchContext: NSManagedObjectContext?
    public private(set) var spotlightIndexer: RpgSpotlightIndexerDelegate?

    private var inMemory: Bool
    private var currentActor: AppPersistentActor
    private var localPersistence: CoreDataPersistenceController?
    private var cloudPersistence: CloudKitCoreDataPersistenceController?
    
    public private(set) var hasError: Bool = false
    public private(set) var errorMessage: LocalizedStringResource = ""
    public private(set) var canRecover: Bool = false
    public private(set) var accountAvailable: Bool = false
    
    public var hasCloudKit = false
    public var hasContextSet = false
    public var coreDataInitModel: CoreDataInitModel?
    
    @MainActor
    public init(inMemory: Bool = false, useCloudKit: Bool, currentActor: AppPersistentActor) {
#if !os(tvOS)
        if !inMemory {
            hasCloudKit = useCloudKit
        }
#endif
        self.inMemory = inMemory
        self.currentActor = currentActor
        if hasCloudKit {
            cloudPersistence = CloudKitCoreDataPersistenceController(inMemory: inMemory, currentActor: currentActor)
        } else {
            localPersistence = CoreDataPersistenceController(inMemory: inMemory, currentActor: currentActor)
        }
    }
    
    @MainActor public func setup() {
        if hasCloudKit {
            localPersistence = nil
            if cloudPersistence == nil {
                cloudPersistence = CloudKitCoreDataPersistenceController(inMemory: false, currentActor: currentActor)
            }
            cloudPersistence?.loadDatabase(bundles: Self.rpgModuleBundles)
        } else {
            cloudPersistence = nil
            if localPersistence == nil {
                localPersistence = CoreDataPersistenceController(inMemory: false, currentActor: currentActor)
            }
            localPersistence?.loadDatabase(bundles: Self.rpgModuleBundles)
        }
        finishSetup()
    }
    
    public func resetDatabase(useCloudKit: Bool) -> Bool {
#if !os(tvOS)
        if hasCloudKit != useCloudKit {
            hasCloudKit = useCloudKit
            hasContextSet = false
            return true
        }
#endif
        return false
    }
    
    private func finishSetup() {
        let error = (hasCloudKit ? cloudPersistence?.model.error : localPersistence?.model.error) ?? .none
        coreDataInitModel = hasCloudKit ? cloudPersistence?.model : localPersistence?.model
        switch error {
        case .none:
            guard !hasContextSet else { return }
            if hasCloudKit {
                context = cloudPersistence?.model.context
                batchContext = cloudPersistence?.model.batchContext
                spotlightIndexer = cloudPersistence?.model.spotlightIndexer
            } else {
                context = localPersistence?.model.context
                batchContext = localPersistence?.model.batchContext
                spotlightIndexer = localPersistence?.model.spotlightIndexer
            }
            hasContextSet = true
            return
        case .loadModel:
            errorMessage = "The database models can not be loaded. That means the app bundle is defect. Therefore delete the app and reinstall it. Sorry no recovery possible."
        case .removeFile(let message):
            errorMessage = "The database cannot be removed from the device. The app cannot recover by itself. The underlaying error: \(message)"
        case .migration(let message):
            errorMessage = "The database cannot be loaded. The underlaying error: \(message). But we can recover the app by removing the database file. All data will be lost if you click remove database."
            canRecover = true
        case .creation(let message):
            errorMessage = "The database cannot be recreated on the device. This should never happen. Hardware defect? The underlaying error: \(message)"
        @unknown default:
            fatalError()
        }
        hasError = true
    }
    
    @MainActor
    public func deleteDatabase() {
        if hasCloudKit {
            cloudPersistence?.recoverFromError()
        } else {
            localPersistence?.recoverFromError()
        }
        finishSetup()
    }
    
    public var container: NSPersistentContainer? {
        hasCloudKit ? cloudPersistence?.model.container : localPersistence?.model.container
    }
}

extension DataBaseModel {
    @MainActor
    public static var preview: DataBaseModel {
        let model = DataBaseModel(inMemory: true, useCloudKit: false, currentActor: .mainApp)
        model.setup()
        return model
    }
    
    @MainActor
    public static func previewWithOutSetup() -> DataBaseModel {
        DataBaseModel(inMemory: true, useCloudKit: false, currentActor: .mainApp)
    }
}
