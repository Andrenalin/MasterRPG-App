// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum RootRoute: Hashable, Codable {
    /// The `@SceneStorage` key the root navigation layouts restore their selected route from.
    /// See CODE_AUDIT_18 §9.17.
    static let sceneStorageKey = "RootRoute"
    /// visionOS' `SplitVisionNavigation` stores its route under its own, older key on purpose:
    /// existing scenes keep their state under it, so it must not be renamed. See CODE_AUDIT_19 §9.8.
    static let visionSceneStorageKey = "GameRoute"
    /// The editor window's own key: it shares neither the tab selection nor the restored route
    /// of the main window. See CODE_AUDIT_26 §5.124.
    static let editorSceneStorageKey = "EditorRoute"
    /// The first route of a new scene.
    static var defaultRoute: RootRoute { .game }
    /// The first route of a new scene in `TabSidebar`, which has no Game tab.
    static var defaultSidebarRoute: RootRoute { .adventures }

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
    
    public static var visionTabs: [RootRoute] {
        [.game, .adventures, .values, .dice, .search, .settings]
    }

    public static var visionEditorTabs: [RootRoute] {
        [.rules, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
    }

    static var fiveTabs: [RootRoute] {
        [.game, .adventures, .values, .editors, .search]
    }
}
