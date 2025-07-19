// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import os.log

import PhotoRPG
import SpaceRPG

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    @MainActor
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
}

@MainActor @Observable
public final class AppModel: Sendable {

    public var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PhotoDataModel.self, PhotoEntryDataModel.self, SpaceDataModel.self, SpaceEntryDataModel.self,
        ])
        let storeURL = FileManager.groupURL.appending(path: "masterRPG.sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Other Models
    public let deviceRotationModel: DeviceRotationModel

    // Module Root Controller Models

//    public var adventureRoot: AdventureRoot { _adventureRoot.unsafelyUnwrapped }
//    public var audioRoot: AudioRoot { _audioRoot.unsafelyUnwrapped }
//    public var diceRoot: DiceRoot { _diceRoot.unsafelyUnwrapped }
//    public var gameRoot: GameRoot { _gameRoot.unsafelyUnwrapped }
//    public var mapRoot: MapRoot { _mapRoot.unsafelyUnwrapped }
//    public var pdfRoot: PdfRoot { _pdfRoot.unsafelyUnwrapped }
//    public var photoRoot: PhotoRoot { _photoRoot.unsafelyUnwrapped }
//    public var spaceRoot: SpaceRoot { _spaceRoot.unsafelyUnwrapped }
//    public var tableRoot: TableRoot { _tableRoot.unsafelyUnwrapped }
//    public var valueRoot: ValueRoot { _valueRoot.unsafelyUnwrapped }
//    public var weatherRoot: WeatherRoot { _weatherRoot.unsafelyUnwrapped }

    // Routing models
    public var navigator: Navigator

    // Iืืnternals
//    @ObservationIgnored private var _adventureRoot: AdventureRoot?
//    @ObservationIgnored private var _audioRoot: AudioRoot?
//    @ObservationIgnored private var _diceRoot: DiceRoot?
//    @ObservationIgnored private var _gameRoot: GameRoot?
//    @ObservationIgnored private var _mapRoot: MapRoot?
//    @ObservationIgnored private var _pdfRoot: PdfRoot?
//    @ObservationIgnored private var _photoRoot: PhotoRoot?
//    @ObservationIgnored private var _spaceRoot: SpaceRoot?
//    @ObservationIgnored private var _tableRoot: TableRoot?
//    @ObservationIgnored private var _valueRoot: ValueRoot?
//    @ObservationIgnored private var _weatherRoot: WeatherRoot?

    @MainActor
    public init() {
        self.deviceRotationModel = DeviceRotationModel()
        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.0", executionDelay: 0.4, verbosity: .info))
    }
}

// MARK: - Routing

extension AppModel {
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
    
//    @MainActor
//    public var routeActions: RouteActions {
//        RouteActions { [weak self] module, itemId, entryId in
//            guard module != .none, let itemId else { return }
//            self?.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: entryId))
//        }
//    }
}
