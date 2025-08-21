// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import os.log

import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    @MainActor
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
}

@MainActor @Observable
public final class AppModel: Sendable {

    // DB
    public let modelContainer: ModelContainer

    // other models
    public let deviceRotationModel: DeviceRotationModel
    public let windowStateModel: WindowStateModel
    
    // Module roots
    public var audioRoot: AudioRootModel
    public var diceRoot: DiceRootModel
    public var pdfRoot: PdfRootModel
    public var photoRoot: PhotoRootModel
    public var spaceRoot: SpaceRootModel

    // Routing models
    public var navigator: Navigator

    @MainActor
    public init() {
        let modelContainer = Self.initModelContainer()
        self.modelContainer = modelContainer

        self.deviceRotationModel = DeviceRotationModel()
        self.windowStateModel = WindowStateModel()
        
        self.audioRoot = AudioRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.diceRoot = DiceRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.pdfRoot = PdfRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.photoRoot = PhotoRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContainer.mainContext)

        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.2", executionDelay: 0.4, verbosity: .info))
    }
    
    @MainActor
    private static func initModelContainer() -> ModelContainer {
        let schema = Schema(
            [
                TagDataModel.self,
                ItemDataModel.self,
                EntryDataModel.self,
                AudioDataModel.self,
                AudioEntryDataModel.self,
                DiceDataModel.self,
                DiceEntryDataModel.self,
                PdfDataModel.self,
                PdfEntryDataModel.self,
                PhotoDataModel.self,
                PhotoEntryDataModel.self,
                SpaceDataModel.self,
                SpaceEntryDataModel.self,
            ]
        )
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}


// MARK: Window Management

public extension AppModel {
    func windowPlacement(for module: NetworkModules) -> WindowPlacementPosition {
        switch module {
        case .none, .setting, .editor, .game, .search:
            return .leading(WindowIdentifier.game.rawValue)
        case .photo:
//            if settingsModel.gameModus == .player {
//                return .leading(WindowIdentifier.game.rawValue, fallback: nil)
//            }
            return
                .above(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .map:
            return .trailing(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .table:
            return .leading(WindowIdentifier.game.rawValue)
        case .adventure:
            return .trailing(WindowIdentifier.game.rawValue)
        case .dice:
//            if settingsModel.gameModus == .player {
//                return .trailing(NetworkModules.value.linkWindowId, fallback: WindowIdentifier.game.rawValue)
//            }
            return .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .weather:
            return .above(NetworkModules.map.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .value:
//            if settingsModel.gameModus == .player {
//                return .trailing(WindowIdentifier.game.rawValue, fallback: nil)
//            }
            return .above(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            
        case .audio:
//            if settingsModel.gameModus == .player {
//                return .leading(NetworkModules.photo.linkWindowId, fallback: WindowIdentifier.game.rawValue)
//            }
            return .below(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .pdf:
            return .leading(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        case .space:
//            if settingsModel.gameModus == .player {
//                return .leading(NetworkModules.photo.linkWindowId, fallback: WindowIdentifier.game.rawValue)
//            }
            return .below(NetworkModules.map.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        @unknown default:
            fatalError()
        }
    }
}
