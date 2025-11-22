// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import CoreData
import Observation
import SwiftData
import SwiftUI
import os.log

import RPGAdventures
import RPGDie
import RPGAudios
import RPGGame
import RPGMaps
import RPGPdfs
import PhotoRPG
import RPGResources
import SpaceRPG
import RPGTables
import RPGValues
import RPGWeathers

#if !os(tvOS)
import GeneratorRPG
#endif

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    @MainActor
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
}

@MainActor @Observable
public final class AppModel: Sendable {
    @MainActor public static let shared = AppModel()
    
    // Other Models
    @ObservationIgnored public let deviceRotationModel: DeviceRotationModel
    @ObservationIgnored public let optionKeyDownModel: OptionKeyDownModel
    @ObservationIgnored public var rpgSpotlightIndexer: RpgSpotlightIndexerDelegate?
    @ObservationIgnored public let settingsModel: AppSettingsModel
    @ObservationIgnored public var selectionSheetLinkModel: SelectionSheetLinkModel
    @ObservationIgnored public let windowStateModel: WindowStateModel
    
    // Options
    public var hasDatabase: Bool = false
    
    @ObservationIgnored let inAppModel = InAppModel()
    public let inAppController: InAppController
    
    // Routing models
    @ObservationIgnored public var navigator: Navigator
    var selectedModule: RootRoute? = .game
    var selectedExtendedModule: ExtendedTabRoute? = nil
    var menuSelectedModule: NetworkModules = .game
    
    // Module roots
    @ObservationIgnored public let adventureRoot: AdventureRootModel
    @ObservationIgnored public let audioRoot: AudioRootModel
    @ObservationIgnored public let diceRoot: DiceRootModel
    @ObservationIgnored public let gameRoot: GameRoot
    @ObservationIgnored public let mapRoot: MapRootModel
    @ObservationIgnored public let pdfRoot: PdfRootModel
    @ObservationIgnored public let photoRoot: PhotoRootModel
    @ObservationIgnored public let spaceRoot: SpaceRootModel
    @ObservationIgnored public let tableRoot: TableRootModel
    @ObservationIgnored public let valueRoot: CharacterRootModel
    @ObservationIgnored public let weatherRoot: WeatherRootModel
    
#if !os(tvOS)
    @ObservationIgnored public let generatorRoot: GeneratorRootModel
#endif

    private let root: RootManager
    
    @MainActor public init() {
        self.deviceRotationModel = DeviceRotationModel()
        self.optionKeyDownModel = OptionKeyDownModel()
        self.settingsModel = AppSettingsModel()
        self.selectionSheetLinkModel = SelectionSheetLinkModel()
        self.windowStateModel = WindowStateModel()
        
        self.inAppController = InAppController(model: inAppModel)
        
        self.navigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "1.0.13",
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        let diceRoot = DiceFactory.root(container: modelContainer)
        let photoRoot = PhotoFactory.root(container: modelContainer)
        let audioRoot = AudioFactory.root(container: modelContainer)
        let pdfRoot = PdfFactory.root(container: modelContainer)
        let spaceRoot = SpaceFactory.root(container: modelContainer)
        
        let tableRoot = TableFactory.root(container: modelContainer, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let weatherRoot = WeatherRootFactory.root(container: modelContainer, photoRoot: photoRoot)
        
        let valueRoot = ValueFactory.root(container: modelContainer, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        
        let mapRoot = MapFactory.root(container: modelContainer, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
        let adventureRoot = AdventureFactory.root(container: modelContainer, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
        let gameRoot = GameRoot(adventureRoot: adventureRoot, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
        
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.gameRoot = gameRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.valueRoot = valueRoot
        self.weatherRoot = weatherRoot
        
#if os(tvOS)
        root = RootManager(
            adventureRoot: spaceRoot,
            audioRoot: spaceRoot,
            characterRoot: spaceRoot,
            diceRoot: spaceRoot,
            generatorRoot: spaceRoot,
            mapRoot: spaceRoot,
            pdfRoot: spaceRoot,
            photoRoot: spaceRoot,
            spaceRoot: spaceRoot,
            tableRoot: spaceRoot,
            weatherRoot: spaceRoot
        )
        
#else
        
        let generatorRoot = GeneratorRootFactory.rootModel(container: modelContainer)
        self.generatorRoot = generatorRoot
        
        root = RootManager(
            adventureRoot: spaceRoot,
            audioRoot: spaceRoot,
            characterRoot: spaceRoot,
            diceRoot: spaceRoot,
            generatorRoot: spaceRoot,
            mapRoot: spaceRoot,
            pdfRoot: spaceRoot,
            photoRoot: spaceRoot,
            spaceRoot: spaceRoot,
            tableRoot: spaceRoot,
            weatherRoot: spaceRoot
        )
#endif

    }
}
 
// MARK: - Maintanence

extension AppModel {
    public func resetData() async {
        await adventureRoot.resetData()
    }

    public func save() async {
        await adventureRoot.save()
    }

    public func installExampleData(isGerman: Bool = false) {
        let importController = adventureRoot.importControllable
        let bundle = Resources.bundle
        let name = isGerman ? Resources.exampleFirstGermanData : Resources.exampleFirstData
        guard let url = bundle.url(forResource: name, withExtension: "gmz") else { return }
        let task = importController.importUrl(from: url)
        Task {
            let _ = await task.result
        }
    }

    func loadFreePackages(tag: String) {
        let importController = adventureRoot.importControllable
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: tag, withExtension: "gmz") else { return }
        let task = importController.importUrl(from: url)
        Task {
            let _ = await task.result
        }
    }

    public func windowPlacement(for module: NetworkModules) -> WindowPlacementPosition {
        switch module {
        case .none, .setting, .editor, .game, .generator, .search:
                return .leading(WindowIdentifier.game.rawValue)
            case .photo:
                if settingsModel.gameModus == .player {
                    return .leading(WindowIdentifier.game.rawValue, fallback: nil)
                }
                return
                    .above(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .map:
                return .trailing(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .table:
                return .leading(WindowIdentifier.game.rawValue)
            case .adventure:
                return .trailing(WindowIdentifier.game.rawValue)
            case .dice:
                if settingsModel.gameModus == .player {
                    return .trailing(NetworkModules.value.linkWindowId, fallback: WindowIdentifier.game.rawValue)
                }
                return .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .weather:
                return .above(NetworkModules.map.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .value:
                if settingsModel.gameModus == .player {
                    return .trailing(WindowIdentifier.game.rawValue, fallback: nil)
                }
                return .above(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)

            case .audio:
                if settingsModel.gameModus == .player {
                    return .leading(NetworkModules.photo.linkWindowId, fallback: WindowIdentifier.game.rawValue)
                }
                return .below(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .pdf:
                return .leading(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue)
            case .space:
                if settingsModel.gameModus == .player {
                    return .leading(NetworkModules.photo.linkWindowId, fallback: WindowIdentifier.game.rawValue)
                }
                return .below(NetworkModules.map.linkWindowId, fallback: WindowIdentifier.game.rawValue)
        @unknown default:
            fatalError()
        }
    }
}

// MARK: - DB and Root Models setup

extension AppModel {
    @MainActor public func setupRootModels(context: NSManagedObjectContext, spotlightIndexer: RpgSpotlightIndexerDelegate?) {
        adventureRoot.setUp(context: context)
        generatorRoot.setUp(context: context, rootControllable: adventureRoot)
        
        self.rpgSpotlightIndexer = spotlightIndexer
        spotlightIndexer?.observeIndexing()
        
        hasDatabase = true
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

    
    @MainActor var externalRouter: any NavigationRouting<KnownRoutes> {
        NavigationRouter(navigator) { route in
            switch route {
            case .adventures:
                self.navigator.perform(route: KnownRoutes.adventures(nil, nil))
            case .audios:
                self.navigator.perform(route: KnownRoutes.audios(nil, nil))
            default:
                break
            }
        }
    }
    
    @MainActor public var routeActions: RouteActions {
        RouteActions { [weak self] module, itemId, entryId in
            guard module != .none, let itemId else { return }
            self?.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: entryId))
        }
    }
}

extension AppModel {
    @MainActor public static var preview: AppModel {
        let dbModel = DataBaseModel.preview
        let model = AppModel()
        model.setupRootModels(context: dbModel.context.unsafelyUnwrapped, spotlightIndexer: nil)
        return model
    }
    @MainActor public static let previewWithoutDatabase: AppModel = AppModel()
}
