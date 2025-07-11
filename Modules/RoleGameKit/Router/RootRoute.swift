// @copyright André Trettin

import AndrenalinKit
import PhotoRPG
import RPGAdventures
import RPGAudios
import RPGDie
import RPGGame
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers
import SwiftUI

public enum RootRoute: Hashable, Codable {
    case adventures(UUID)
    case audios(UUID)
    case dice(UUID)
    case editors(UUID)
    case game
    case maps(UUID)
    case pdfs(UUID)
    case photos(UUID)
    case settings
    case space(UUID)
    case tables(UUID)
    case values(UUID)
    case weathers(UUID)
    
    public init(networkModule: NetworkModules, tabId: UUID) {
        switch networkModule {
        case .none:
            self = .game
        case .photo:
            self = .photos(tabId)
        case .map:
            self = .maps(tabId)
        case .table:
            self = .tables(tabId)
        case .adventure:
            self = .adventures(tabId)
        case .dice:
            self = .dice(tabId)
        case .value:
            self = .values(tabId)
        case .weather:
            self = .weathers(tabId)
        case .game:
            self = .game
        case .audio:
            self = .audios(tabId)
        case .pdf:
            self = .pdfs(tabId)
        case .space:
            self = .space(tabId)
        case .setting:
            self = .settings
        case .editor:
            self = .editors(tabId)
        @unknown default:
            fatalError()
        }
    }
    
    public var module: NetworkModules {
        switch self {
        case .game:
            return .game
        case .values:
            return .value
        case .adventures:
            return .adventure
        case .maps:
            return .map
        case .tables:
            return .table
        case .photos:
            return .photo
        case .weathers:
            return .weather
        case .dice:
            return .dice
        case .audios:
            return .audio
        case .pdfs:
            return .pdf
        case .settings:
            return .setting
        case .editors:
            return .editor
        case .space:
            return .space
        }
    }
}

extension RootRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
            case .adventures(let id): "\(module.token)/\(id.uuidString)"
            case .audios(let id): "\(module.token)/\(id.uuidString)"
            case .dice(let id): "\(module.token)/\(id.uuidString)"
            case .editors(let id): "\(module.token)/\(id.uuidString)"
            case .game: "\(module.token)/C352A849-80F9-48B3-9010-8E1B49367192"
            case .maps(let id): "\(module.token)/\(id.uuidString)"
            case .pdfs(let id): "\(module.token)/\(id.uuidString)"
            case .photos(let id): "\(module.token)/\(id.uuidString)"
            case .settings: "\(module.token)/C352A849-80F9-48B3-9010-8E1B49367192"
            case .space(let id): "\(module.token)/\(id.uuidString)"
            case .tables(let id): "\(module.token)/\(id.uuidString)"
            case .values(let id): "\(module.token)/\(id.uuidString)"
            case .weathers(let id): "\(module.token)/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
            case NetworkModules.adventure.token: self = .adventures(uuid)
            case NetworkModules.audio.token: self = .audios(uuid)
            case NetworkModules.dice.token: self = .dice(uuid)
            case NetworkModules.editor.token: self = .editors(uuid)
            case NetworkModules.game.token: self = .game
            case NetworkModules.map.token: self = .maps(uuid)
            case NetworkModules.pdf.token: self = .pdfs(uuid)
            case NetworkModules.photo.token: self = .photos(uuid)
            case NetworkModules.setting.token: self = .settings
            case NetworkModules.space.token: self = .space(uuid)
            case NetworkModules.table.token: self = .tables(uuid)
            case NetworkModules.value.token: self = .values(uuid)
            case NetworkModules.weather.token: self = .weathers(uuid)
            default: self = .game
        }
    }
}

extension RootRoute: AppRouter {
    public var title: String {
        String(module.title)
    }
    
    public var icon: String {
        module.icon
    }
}

extension RootRoute: NavigationDestination {
    public var body: some View {
        RouteRouteDestionationView(route: self)
    }
    
    static func allTabs(for tabId: UUID) -> [RootRoute] {
#if os(iOS) || os(visionOS)
        [.game, .adventures(tabId), .values(tabId), .pdfs(tabId), .tables(tabId), .maps(tabId), .photos(tabId), .audios(tabId), .space(tabId), .weathers(tabId), .dice(tabId), .settings]
#else
        [.adventures(tabId), .values(tabId), .pdfs(tabId), .tables(tabId), .maps(tabId), .photos(tabId), .audios(tabId), .space(tabId), .weathers(tabId), .dice(tabId)]
#endif
    }
    
    static func fiveTabs(for tabId: UUID) -> [RootRoute] {
        [.game, .adventures(tabId), .values(tabId), .editors(tabId), .settings]
    }
        
    static func splitLeadingTabs(for tabId: UUID) -> [RootRoute] {
        [.game, .adventures(tabId), .values(tabId), .pdfs(tabId), .tables(tabId), .editors(tabId), .settings]
    }
    
    static func splitTrailingTabs(for tabId: UUID) -> [RootRoute] {
        [.maps(tabId), .photos(tabId), .audios(tabId), .space(tabId), .weathers(tabId), .dice(tabId)]
    }
}

struct RouteRouteDestionationView: View {
    let route: RootRoute
    
    @Environment(AppStore.self) private var appStore
    
    var body: some View {
        switch route {
        case .adventures(let tabId):
            AdventureFactory.rootView(for: appStore.adventureRoot, tabId: tabId)
                .environment(appStore.adventureRoot)
        case .audios(let tabId):
            AudioFactory.rootView(for: appStore.audioRoot, tabId: tabId)
                .environment(appStore.audioRoot)
        case .dice(let tabId):
            DiceFactory.rootView(for: appStore.diceRoot, tabId: tabId)
                .environment(appStore.diceRoot)
        case .editors(let tabId):
#if os(visionOS)
            EmptyView()
#else
            ExtendedTabBar(tabId: tabId)
#endif
        case .game:
            appStore.gameRoot.viewController.gameTabItem()
        case .maps(let tabId):
            MapFactory.rootView(for: appStore.mapRoot, tabId: tabId)
                .environment(appStore.mapRoot)
        case .pdfs(let tabId):
            PdfFactory.rootView(for: appStore.pdfRoot, tabId: tabId)
                .environment(appStore.pdfRoot)
        case .photos(let tabId):
            NewPhotoRoute(appStore: appStore, tabId: tabId, isExtended: false)
        case .space(let tabId):
            SpaceFactory.rootView(for: appStore.spaceRoot, tabId: tabId)
                .environment(appStore.spaceRoot)
        case .settings:
            SettingsView(store: appStore)
        case .tables(let tabId):
            TableFactory.rootView(for: appStore.tableRoot, tabId: tabId)
                .environment(appStore.tableRoot)
        case .values(let tabId):
            ValueFactory.rootView(for: appStore.valueRoot, tabId: tabId)
                .environment(appStore.valueRoot)
        case .weathers(let tabId):
            WeatherFactory.rootView(for: appStore.weatherRoot, tabId: tabId)
                .environment(appStore.weatherRoot)
        }
    }
}
