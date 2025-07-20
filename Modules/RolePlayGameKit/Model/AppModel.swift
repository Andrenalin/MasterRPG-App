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

    // DB
    public let modelContainer: ModelContainer

    // other models
    public let deviceRotationModel: DeviceRotationModel

    // Module roots
    public var photoRoot: PhotoRootModel
    public var spaceRoot: SpaceRootModel

    // Routing models
    public var navigator: Navigator

    @MainActor
    public init() {
        self.deviceRotationModel = DeviceRotationModel()
        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.0", executionDelay: 0.4, verbosity: .info))
        let modelContainer = Self.initModelContainer()
        self.modelContainer = modelContainer
        self.photoRoot = PhotoRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContainer.mainContext)
    }
    
    @MainActor
    private static func initModelContainer() -> ModelContainer {
        let schema = Schema([
            PhotoDataModel.self, PhotoEntryDataModel.self, SpaceDataModel.self, SpaceEntryDataModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
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
            case .photos(let itemId, let entryId):
                self.navigator.perform(route: KnownRoutes.photos(itemId, entryId))
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
