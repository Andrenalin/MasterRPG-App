// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import AudioRPG
import DiceRPG
import RPGGame
import RPGMaps
import PdfRPG
import PhotoRPG
import SpaceRPG
import RPGTables
import RPGValues
import WeatherRPG
import SwiftUI

#if !os(tvOS)
import GeneratorRPG
#endif

public enum RootRoute: Hashable, Codable {
    case adventures
    case audios
    case dice
    case editors
    case game
    case generator
    case maps
    case pdfs
    case photos
    case search
    case settings
    case space
    case tables
    case values
    case weathers
    
    public init(networkModule: NetworkModules) {
        switch networkModule {
        case .adventure: self = .adventures
        case .audio: self = .audios
        case .dice: self = .dice
        case .editor: self = .editors
        case .generator: self = .generator
        case .map: self = .maps
        case .pdf: self = .pdfs
        case .photo: self = .photos
        case .setting: self = .settings
        case .space: self = .space
        case .search: self = .search
        case .table: self = .tables
        case .value: self = .values
        case .weather: self = .weathers
        default: self = .game
        }
    }
    
    public var module: NetworkModules {
        switch self {
        case .adventures: .adventure
        case .audios: .audio
        case .dice: .dice
        case .editors: .editor
        case .game: .game
        case .generator: .generator
        case .maps: .map
        case .pdfs: .pdf
        case .photos: .photo
        case .tables: .table
        case .search: .search
        case .settings: .setting
        case .space: .space
        case .values: .value
        case .weathers: .weather
        }
    }
    
    public var hasDetailView: Bool {
        switch self {
        case .game, .settings, .search: false
        default: true
        }
    }
}

extension RootRoute: RawRepresentable {
    public var rawValue: String {
        module.token
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case NetworkModules.adventure.token: self = .adventures
        case NetworkModules.audio.token: self = .audios
        case NetworkModules.dice.token: self = .dice
        case NetworkModules.editor.token: self = .editors
        case NetworkModules.game.token: self = .game
        case NetworkModules.generator.token: self = .generator
        case NetworkModules.map.token: self = .maps
        case NetworkModules.pdf.token: self = .pdfs
        case NetworkModules.photo.token: self = .photos
        case NetworkModules.search.token: self = .search
        case NetworkModules.setting.token: self = .settings
        case NetworkModules.space.token: self = .space
        case NetworkModules.table.token: self = .tables
        case NetworkModules.value.token: self = .values
        case NetworkModules.weather.token: self = .weathers
        default: self = .game
        }
    }
}

extension RootRoute {
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
    
    public static var allTabs: [RootRoute] {
        [.game, .adventures, .values, .generator, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings, .search]
    }

    public static var macTabs: [RootRoute] {
        [.adventures, .values, .generator, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .search]
    }

    static var fiveTabs: [RootRoute] {
        [.game, .adventures, .values, .editors, .search]
    }
}

struct RouteRouteDestionationView: View {
    let route: RootRoute
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        Group {
            switch route {
            case .adventures:
                NewAdventureRoute(appModel: appModel, tabId: KnownRoutes.mainTabId, isExtended: false)
            case .audios:
                AudioFactory.rootView()
            case .dice:
                DiceFactory.rootView()
            case .editors:
#if os(visionOS)
                EmptyView()
#else
                ExtendedTabBar()
#endif
            case .game:
                appModel.gameRoot.viewController.gameTabItem()
            case .generator:
#if os(tvOS)
                EmptyView()
#else
                GeneratorRootFactory.rootView()
#endif
            case .maps:
                NewMapRoute(appModel: appModel, tabId: KnownRoutes.mainTabId, isExtended: false)
            case .pdfs:
                PdfFactory.rootView()
            case .photos:
                PhotoFactory.rootView()
            case .space:
                SpaceFactory.rootView()
            case .settings:
                SettingsView(store: appModel)
            case .tables:
                NewTableRoute(appModel: appModel, tabId: KnownRoutes.mainTabId, isExtended: false)
            case .values:
                NewValueRoute(appModel: appModel, tabId: KnownRoutes.mainTabId, isExtended: false)
            case .weathers:
                WeatherRootFactory.rootView()
            case .search:
                Text("Coming Soon")
            }
        }
        .tint(route.module.tint)
        .accentColor(route.module.tint)
    }
}
