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
import GameRPG
import GeneratorRPG
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
    public var isNewUICode: Bool = false
    
    // DB
    @ObservationIgnored public let modelContainer: ModelContainer

    // other models
    @ObservationIgnored public let deviceRotationModel: DeviceRotationModel
    @ObservationIgnored public let settingsModel: AppSettingsModel
    @ObservationIgnored public let windowStateModel: WindowStateModel
    
    // Module roots
    @ObservationIgnored public let adventureRoot: AdventureRootModel
    @ObservationIgnored public let audioRoot: AudioRootModel
    @ObservationIgnored public let characterRoot: CharacterRootModel
    @ObservationIgnored public let diceRoot: DiceRootModel
    @ObservationIgnored public let gameRoot: GameRootController
    @ObservationIgnored public let generatorRoot: GeneratorRootModel
    @ObservationIgnored public let mapRoot: MapRootModel
    @ObservationIgnored public let pdfRoot: PdfRootModel
    @ObservationIgnored public let photoRoot: PhotoRootModel
    @ObservationIgnored public let spaceRoot: SpaceRootModel
    @ObservationIgnored public let tableRoot: TableRootModel
    @ObservationIgnored public let weatherRoot: WeatherRootModel
    
    private let root: RootManager

    // Routing models
    @ObservationIgnored public let navigator: Navigator
    var selectedModule: RootRoute? = .game

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
        
        let generatorRoot = GeneratorRootFactory.rootModel(modelContext: modelContainer.mainContext, adventureRoot: adventureRoot, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot)
        
        let root = RootManager(
            adventureRoot: adventureRoot,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            generatorRoot: generatorRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )

        let gameRoot = GameRootFactory.rootController(
            root: root,
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
        
        self.root = root
        
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.gameRoot = gameRoot
        self.generatorRoot = generatorRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
        
        self.navigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "1.0.9",
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        
        self.linkRootController = LinkRootController(container: modelContainer, root: root)
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
                GeneratorDataModel.self,
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
    
    public subscript(_ module: NetworkModules) -> (any ItemRootControllable)? {
        root[module]
    }
}


// MARK: Window Management

public extension AppModel {
    func windowPlacement(for module: NetworkModules) -> WindowPlacementPosition {
        switch module {
        case .none, .setting, .editor, .game, .search, .generator:
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
    func itemRootController(for module: NetworkModules) -> ItemRootController? {
        root.itemRootController(for: module)
    }
        
    public func resetNavigation() {
        guard let selectedTab: NetworkModules = selectedModule?.module else { return }
        let itemId: UUID? = root[selectedTab]?.currentSelectedItemId
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
            for module in [NetworkModules.dice, .space, .audio, .photo, .pdf, .weather, .table, .value, .map, .adventure, .generator] {
                await self.root[module]?.itemControllable.update(items: items.filter { $0.module == module })
            }
        }
    }
}
