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
    case rules
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
        case .rule: self = .rules
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
        case .rules: .rule
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

    /// Derived from `init(networkModule:)` rather than hand-rolling a second
    /// token-to-case table, so the module list only needs to be kept in sync in one place.
    public init?(rawValue: String) {
        guard let networkModule = NetworkModules.allCases.first(where: { $0.token == rawValue }) else {
            return nil
        }
        self.init(networkModule: networkModule)
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
        RouteDestinationView(route: self)
    }
    
    public static var allTabs: [RootRoute] {
        [.game, .adventures, .values, .rules, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings, .search]
    }

    public static var visionTabs: [RootRoute] {
        [.game, .adventures, .values, .search, .settings]
    }

    public static var visionEditorTabs: [RootRoute] {
        [.rules, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
    }

    static var fiveTabs: [RootRoute] {
        [.game, .adventures, .values, .editors, .search]
    }
}
