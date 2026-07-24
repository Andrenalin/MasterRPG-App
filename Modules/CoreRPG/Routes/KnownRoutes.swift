// @copyright André Trettin

import SwiftUI

public enum KnownRoutes: NavigationRoutes {
    case adventures(UUID?, UUID?)
    case audios(UUID?, UUID?)
    case dice(UUID?, UUID?)
    case game
    case generators(UUID?, UUID?)
    case maps(UUID?, UUID?)
    case pdfs(UUID?, UUID?)
    case photos(UUID?, UUID?)
    case rules(UUID?, UUID?)
    case search
    case settings
    case spaces(UUID?, UUID?)
    case tables(UUID?, UUID?)
    case values(UUID?, UUID?)
    case weathers(UUID?, UUID?)
}

extension KnownRoutes {
    public static let mainTabId: UUID = UUID()
    
    public static func route(module: NetworkModules, itemId: UUID?, entryId: UUID?) -> KnownRoutes {
        switch module {
        case .adventure: .adventures(itemId, entryId)
        case .audio: .audios(itemId, entryId)
        case .dice: .dice(itemId, entryId)
        case .game: .game
        case .generator: .generators(itemId, entryId)
        case .map: .maps(itemId, entryId)
        case .pdf: .pdfs(itemId, entryId)
        case .photo: .photos(itemId, entryId)
        case .rule: .rules(itemId, entryId)
        case .search: .search
        case .setting: .settings
        case .space: .spaces(itemId, entryId)
        case .table: .tables(itemId, entryId)
        case .value: .values(itemId, entryId)
        case .weather: .weathers(itemId, entryId)
        default: .game
        }
    }
}

extension EnvironmentValues {
    @Entry public var router: any NavigationRouting<KnownRoutes> = MockNavigationRouter()
}
