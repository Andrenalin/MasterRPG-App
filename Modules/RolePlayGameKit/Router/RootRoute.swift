// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import PhotoRPG
import SpaceRPG
import SwiftUI

public enum RootRoute: Hashable, Codable {
    case adventures
    case audios
    case dice
    case editors
    case game
    case maps
    case pdfs
    case photos
    case settings
    case space
    case tables
    case values
    case weathers
    
    public init(networkModule: NetworkModules, tabId: UUID) {
        switch networkModule {
        case .none:
            self = .game
        case .photo:
            self = .photos
        case .map:
            self = .maps
        case .table:
            self = .tables
        case .adventure:
            self = .adventures
        case .dice:
            self = .dice
        case .value:
            self = .values
        case .weather:
            self = .weathers
        case .game:
            self = .game
        case .audio:
            self = .audios
        case .pdf:
            self = .pdfs
        case .space:
            self = .space
        case .setting:
            self = .settings
        case .editor:
            self = .editors
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
        module.token
    }

    public init?(rawValue: String) {
        switch rawValue {
            case NetworkModules.adventure.token: self = .adventures
            case NetworkModules.audio.token: self = .audios
            case NetworkModules.dice.token: self = .dice
            case NetworkModules.editor.token: self = .editors
            case NetworkModules.game.token: self = .game
            case NetworkModules.map.token: self = .maps
            case NetworkModules.pdf.token: self = .pdfs
            case NetworkModules.photo.token: self = .photos
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
#if os(iOS) || os(visionOS)
        [.game, .adventures, .values, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings]
#else
        [.adventures, .values, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
#endif
    }
    
    static var fiveTabs: [RootRoute] {
        [.game, .adventures, .values, .editors, .settings]
    }
        
    static func splitLeadingTabs() -> [RootRoute] {
        [.game, .adventures, .values, .pdfs, .tables, .editors, .settings]
    }
    
    static func splitTrailingTabs() -> [RootRoute] {
        [.maps, .photos, .audios, .space, .weathers, .dice]
    }
}

struct RouteRouteDestionationView: View {
    let route: RootRoute
    
    @Environment(AppModel.self) private var appModel
        
    var body: some View {
        switch route {
        case .adventures:
            RootListView(rootRoute: route)
        case .audios:
            RootListView(rootRoute: route)
        case .dice:
            RootListView(rootRoute: route)
        case .editors:
#if os(visionOS)
            EmptyView()
#else
            ExtendedTabBar()
#endif
        case .game:
            RootListView(rootRoute: route)
        case .maps:
            RootListView(rootRoute: route)
        case .pdfs:
            RootListView(rootRoute: route)
        case .photos:
            PhotoRootFactory.rootView(withoutNavigation: false)
                .environment(appModel.photoRoot)
        case .space:
            SpaceRootFactory.rootView(withoutNavigation: false)
                .environment(appModel.spaceRoot)
        case .settings:
            RootListView(rootRoute: route)
            //SettingsView()
        case .tables:
            RootListView(rootRoute: route)
        case .values:
            RootListView(rootRoute: route)
        case .weathers:
            RootListView(rootRoute: route)
        }
    }
}
