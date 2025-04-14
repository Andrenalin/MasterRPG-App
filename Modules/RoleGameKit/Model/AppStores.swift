// @copyright André Trettin

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
import RPGPhotos
import RPGResources
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    @MainActor
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
}

@MainActor @Observable
public final class AppStore: Sendable {
    @MainActor
    public static let shared = AppStore()

    // Other Models
    public let windowStateModel: WindowStateModel
    public let optionKeyDownModel: OptionKeyDownModel
    public let settingsModel: AppSettingsModel
    public var selectionSheetLinkModel: SelectionSheetLinkModel
    public let deviceRotationModel: DeviceRotationModel

    // Options
    public var hasDatabase: Bool = false
    public var firstLunch: Bool = true
    
    @ObservationIgnored
    let inAppModel = InAppModel()
    public let inAppController: InAppController

    // Module Root Controller Models

    public var adventureRoot: AdventureRoot { _adventureRoot.unsafelyUnwrapped }
    public var audioRoot: AudioRoot { _audioRoot.unsafelyUnwrapped }
    public var diceRoot: DiceRoot { _diceRoot.unsafelyUnwrapped }
    public var gameRoot: GameRoot { _gameRoot.unsafelyUnwrapped }
    public var mapRoot: MapRoot { _mapRoot.unsafelyUnwrapped }
    public var pdfRoot: PdfRoot { _pdfRoot.unsafelyUnwrapped }
    public var photoRoot: PhotoRoot { _photoRoot.unsafelyUnwrapped }
    public var spaceRoot: SpaceRoot { _spaceRoot.unsafelyUnwrapped }
    public var tableRoot: TableRoot { _tableRoot.unsafelyUnwrapped }
    public var valueRoot: ValueRoot { _valueRoot.unsafelyUnwrapped }
    public var weatherRoot: WeatherRoot { _weatherRoot.unsafelyUnwrapped }

    // Routing models
    public var navigator: Navigator

    // Iืืnternals
    @ObservationIgnored private var _adventureRoot: AdventureRoot?
    @ObservationIgnored private var _audioRoot: AudioRoot?
    @ObservationIgnored private var _diceRoot: DiceRoot?
    @ObservationIgnored private var _gameRoot: GameRoot?
    @ObservationIgnored private var _mapRoot: MapRoot?
    @ObservationIgnored private var _pdfRoot: PdfRoot?
    @ObservationIgnored private var _photoRoot: PhotoRoot?
    @ObservationIgnored private var _spaceRoot: SpaceRoot?
    @ObservationIgnored private var _tableRoot: TableRoot?
    @ObservationIgnored private var _valueRoot: ValueRoot?
    @ObservationIgnored private var _weatherRoot: WeatherRoot?

    @MainActor
    public init() {
        self.windowStateModel = WindowStateModel()
        self.optionKeyDownModel = OptionKeyDownModel()
        self.settingsModel = AppSettingsModel()
        self.selectionSheetLinkModel = SelectionSheetLinkModel()
        self.deviceRotationModel = DeviceRotationModel()
        self.inAppController = InAppController(model: inAppModel)
        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.0", executionDelay: 0.4, verbosity: .info))
    }

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
            case .none, .setting, .editor, .game:
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

extension AppStore {
    @MainActor
    public func setupRootModels(context: NSManagedObjectContext) {
        let diceRoot = DiceFactory.root(for: context)
        let photoRoot = PhotoFactory.root(for: context)
        let audioRoot = AudioFactory.root(for: context)
        let pdfRoot = PdfFactory.root(for: context)
        let spaceRoot = SpaceFactory.root(for: context)

        let tableRoot = TableFactory.root(for: context, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let weatherRoot = WeatherFactory.root(for: context, photoRoot: photoRoot)

        let valueRoot = ValueFactory.root(for: context, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)

        let mapRoot = MapFactory.root(for: context, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
        let adventureRoot = AdventureFactory.root(for: context, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
        let gameRoot = GameRoot(adventureRoot: adventureRoot, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)

        self._adventureRoot = adventureRoot
        self._audioRoot = audioRoot
        self._diceRoot = diceRoot
        self._gameRoot = gameRoot
        self._mapRoot = mapRoot
        self._pdfRoot = pdfRoot
        self._photoRoot = photoRoot
        self._spaceRoot = spaceRoot
        self._tableRoot = tableRoot
        self._valueRoot = valueRoot
        self._weatherRoot = weatherRoot

        audioRoot.setRootControllable(adventureRoot)
        diceRoot.setRootControllable(adventureRoot)
        mapRoot.setRootControllable(adventureRoot)
        pdfRoot.setRootControllable(adventureRoot)
        photoRoot.setRootControllable(adventureRoot)
        spaceRoot.setRootControllable(adventureRoot)
        tableRoot.setRootControllable(adventureRoot)
        valueRoot.setRootControllable(adventureRoot)
        weatherRoot.setRootControllable(adventureRoot)

        hasDatabase = true
    }
}

// MARK: - Routing

extension AppStore {
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
    
    public var routeActions: RouteActions {
        RouteActions { [weak self] module, itemId, entryId in
            guard module != .none, let itemId else { return }
            self?.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: entryId))
        }
    }
}

extension AppStore {
    @MainActor
    public static var preview: AppStore {
        let dbModel = DataBaseModel.preview
        let model = AppStore()
        model.setupRootModels(context: dbModel.context.unsafelyUnwrapped)
        return model
    }
    @MainActor
    public static let previewWithoutDatabase: AppStore = AppStore()
}

//struct DownloadedGamePack {
//    let productID: String
//    let request: NSBundleResourceRequest
//
//    func resourcePath() -> URL? {
//        request.bundle.url(forResource: productID, withExtension: "gmz")
//    }
//
//    func getResourceTag(for productId: String) -> String {
//        productId
//    }
//
//    func downloadGamePack(for productID: String) async throws -> DownloadedGamePack {
//        let request = NSBundleResourceRequest(tags: Set([getResourceTag(for: productID)]))
//        do {
//            try await request.beginAccessingResources()
//            return DownloadedGamePack(productID: productID, request: request)
//        } catch {
//            print(error.localizedDescription)
//            throw error
//        }
//    }
//}
