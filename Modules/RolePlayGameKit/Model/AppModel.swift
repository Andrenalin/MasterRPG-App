// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import RPGResources
import SwiftData
import SwiftUI
import os.log

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

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
    public let settingsModel: AppSettingsModel
    public let windowStateModel: WindowStateModel
    
    // Module roots
    public let adventureRoot: AdventureRootModel
    public let audioRoot: AudioRootModel
    public let characterRoot: CharacterRootModel
    public let diceRoot: DiceRootModel
    public let mapRoot: MapRootModel
    public let pdfRoot: PdfRootModel
    public let photoRoot: PhotoRootModel
    public let spaceRoot: SpaceRootModel
    public let tableRoot: TableRootModel
    public let weatherRoot: WeatherRootModel

    // Routing models
    public let navigator: Navigator

    // Root Controllers
    public let linkRootController: LinkRootController
    
    @MainActor
    public init() {
        let modelContainer = Self.initModelContainer()
        self.modelContainer = modelContainer

        self.deviceRotationModel = DeviceRotationModel()
        self.settingsModel = AppSettingsModel()
        self.windowStateModel = WindowStateModel()
                
        let audioRoot = AudioRootFactory.rootModel(modelContext: modelContainer.mainContext)
        let diceRoot = DiceRootFactory.rootModel(modelContext: modelContainer.mainContext)
        let pdfRoot = PdfRootFactory.rootModel(modelContext: modelContainer.mainContext)
        let photoRoot = PhotoRootFactory.rootModel(modelContext: modelContainer.mainContext)
        let spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContainer.mainContext)
        let tableRoot = TableRootFactory.rootModel(modelContext: modelContainer.mainContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let weatherRoot = WeatherRootFactory.rootModel(modelContext: modelContainer.mainContext, photoRoot: photoRoot)
        let characterRoot = CharacterRootFactory.rootModel(modelContext: modelContainer.mainContext, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = MapRootFactory.rootModel(modelContext: modelContainer.mainContext, characterRoot: characterRoot,  diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let adventureRoot = AdventureRootFactory.rootModel(modelContext: modelContainer.mainContext, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot)
        
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
        
        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.6", executionDelay: 0.4, verbosity: .info))
        
        self.linkRootController = LinkRootController(
            container: modelContainer,
            adventureRoot: adventureRoot,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )
    }
    
    @MainActor
    private static func initModelContainer() -> ModelContainer {
        let schema = Schema(
            [
                ItemDataModel.self,
                EntryDataModel.self,
                LinkDataModel.self,
                TagDataModel.self,
                AdventureDataModel.self,
                CharacterDataModel.self,
                DiceDataModel.self,
                MapDataModel.self,
                PdfEntryDataModel.self,
                TableDataModel.self,
                WeatherDataModel.self,
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
    
    func windowViewerPlacement(for module: NetworkModules) -> WindowPlacementPosition {
        switch module {
        case .pdf: .below(WindowIdentifier.game.rawValue)
        default: .trailing(WindowIdentifier.game.rawValue, fallback: nil)
        }
    }
}

// MARK: - Routing
extension AppModel {
    func resetNavigation(selectedTab: NetworkModules) {
        let itemId: UUID? = switch selectedTab {
        case .adventure: adventureRoot.currentSelectedItemId
        case .audio: audioRoot.currentSelectedItemId
        case .value: characterRoot.currentSelectedItemId
        case .dice: diceRoot.currentSelectedItemId
        case .map: mapRoot.currentSelectedItemId
        case .pdf: pdfRoot.currentSelectedItemId
        case .photo: photoRoot.currentSelectedItemId
        case .space: spaceRoot.currentSelectedItemId
        case .table: tableRoot.currentSelectedItemId
        case .weather: weatherRoot.currentSelectedItemId
        case .editor: nil
        case .game: nil
        case .none: nil
        case .search: nil
        case .setting: nil
        }
        
        Task {
            try await Task.sleep(for: .milliseconds(150))
            navigator.perform(route: KnownRoutes.route(module: selectedTab, itemId: itemId, entryId: nil))
        }
    }
}

extension AppModel {
    func installExampleData(isGerman: Bool = false) {
        let importController = ImportController(appModel: self)
        let bundle = Resources.bundle
        let name = isGerman ? Resources.exampleFirstGermanData : Resources.exampleFirstData
        guard let url = bundle.url(forResource: name, withExtension: "gmz") else { return }
        let task = importController.importUrl(from: url)
        Task {
            let _ = await task.result
        }
    }
}

extension AppModel {
    func update(items: [ItemDataModel]) {
        Task {
            await diceRoot.itemControllable.update(items: items.filter { $0.module == .dice })
            await spaceRoot.itemControllable.update(items: items.filter { $0.module == .space })
            await audioRoot.itemControllable.update(items: items.filter { $0.module == .audio })
            await photoRoot.itemControllable.update(items: items.filter { $0.module == .photo })
            await pdfRoot.itemControllable.update(items: items.filter { $0.module == .pdf })
            await weatherRoot.itemControllable.update(items: items.filter { $0.module == .weather })
            await tableRoot.itemControllable.update(items: items.filter { $0.module == .table })
            await characterRoot.itemControllable.update(items: items.filter { $0.module == .value })
            await mapRoot.itemControllable.update(items: items.filter { $0.module == .map })
            await adventureRoot.itemControllable.update(items: items.filter { $0.module == .adventure })
        }
    }
}
