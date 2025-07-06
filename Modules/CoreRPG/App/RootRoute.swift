// @copyright André Trettin

import SwiftUI

public enum RootRoute: String, Hashable, Codable {
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
    
    public var title: String {
        self.rawValue
    }
    
    public var icon: String {
        switch self {
        case .adventures: "wand.and.stars"
        case .game: "person.2.wave.2"
        case .photos: "photo.on.rectangle.angled"
        case .values: "list.bullet.rectangle"
        case .maps: "map"
        case .tables: "tablecells.fill"
        case .weathers: "cloud.bolt.rain"
        case .dice: "dice"
        case .audios: "music.note.list"
        case .pdfs: "books.vertical"
        case .space: "view.3d"
        case .settings: "gear"
        case .editors: "pencil"
        }
    }
}

public extension RootRoute {    
    static var allTabs: [RootRoute] {
#if os(iOS) || os(visionOS)
        [.game, .adventures, .values, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings]
#else
        [.adventures, .values, .pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
#endif
    }
    
    static func fiveTabs(for tabId: UUID) -> [RootRoute] {
        [.game, .adventures, .values, .editors, .settings]
    }
        
    static func splitLeadingTabs(for tabId: UUID) -> [RootRoute] {
        [.game, .adventures, .values, .pdfs, .tables, .editors, .settings]
    }
    
    static func splitTrailingTabs(for tabId: UUID) -> [RootRoute] {
        [.maps, .photos, .audios, .space, .weathers, .dice]
    }
}
