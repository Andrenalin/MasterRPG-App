// @copyright André Trettin

import CoreRPG
import SwiftUI

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
        case .editors, .game, .settings: false
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
        default: return nil
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
        [.game, .adventures, .values, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings, .search]
    }

    public static var visionTabs: [RootRoute] {
        [.game, .adventures, .values, .search, .settings]
    }

    public static var visionEditorTabs: [RootRoute] {
        [.pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
    }

    static var fiveTabs: [RootRoute] {
        [.game, .adventures, .values, .editors, .search]
    }
}
