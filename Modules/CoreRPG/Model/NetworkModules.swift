// @copyright André Trettin

import Foundation
import SwiftUI

/// The modules of the app.
///
/// Wire format: the raw values travel in every envelope and decode strictly. A peer that does
/// not know a case cannot decode the envelope and drops it, with a decode error and no hint
/// about the version. Adding, removing or renumbering a case therefore changes the wire format:
/// bump `GameNetworkModel.currentVersion` with it (a peer of another version is refused with an
/// explicit "unsupported version" instead). `WireContractTests` pins the cases and the version
/// together so that neither changes alone. See CODE_AUDIT_Game_Shareplay §4.1.
public enum NetworkModules: Int, Codable, Hashable, Sendable, CaseIterable {
    case none = 0
    case photo = 1
    case map = 2
    case table = 3
    case adventure = 4
    case dice = 6
    case weather = 7
    case game = 8
    case value = 9
    case audio = 10
    case pdf = 11
    case space = 12
    case setting = 13
    case editor = 14
    case search = 15
    case generator = 16
    case rule = 17

    /// The modules the master's "open another window" menus offer, in display order —
    /// shared by `MasterModuleWindowMenu` (vertical column) and `GameTableSideMenu`
    /// (horizontal row, which drops `.game` since that button needs `adventureId` and
    /// is handled as its own leading button instead). Previously three hand-copied,
    /// independently-drifting arrays. See CODE_AUDIT §9.7.
    public static let gameWindowMasterModules: [NetworkModules] = [
        .game, .adventure, .audio, .dice, .map, .pdf, .photo, .rule, .space, .table, .value, .weather
    ]

    /// The modules the player's "open another window" menus offer, in display order —
    /// shared by `PlayerSideMenu` (vertical column) and `GameTableSideMenu` (horizontal
    /// row). See CODE_AUDIT §9.7.
    public static let gameWindowPlayerModules: [NetworkModules] = [
        .value, .table, .audio, .photo, .pdf, .space, .dice
    ]

    public var token: String {
        switch self {
        case .adventure: "ADVENTURES"
        case .audio: "AUDIOS"
        case .dice: "DICE"
        case .editor: "EDITOR"
        case .game: "GAME"
        case .generator: "GENERATOR"
        case .pdf: "PDFS"
        case .photo: "PHOTOS"
        case .rule: "RULES"
        case .map: "MAPS"
        case .none: "ERROR"
        case .search: "SEARCH"
        case .setting: "SETTINGS"
        case .space: "SPACES"
        case .table: "TABLES"
        case .value: "VALUES"
        case .weather: "WEATHERS"
        }
    }

    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .adventure: LocalizedStringResource("Adventure", bundle: .module)
        case .audio: LocalizedStringResource("Audio", bundle: .module)
        case .dice: LocalizedStringResource("Dice", bundle: .module)
        case .editor: LocalizedStringResource("Editors", bundle: .module)
        case .game: LocalizedStringResource("Game", bundle: .module)
        case .generator: LocalizedStringResource("Generator", bundle: .module)
        case .map: LocalizedStringResource("Map", bundle: .module)
        case .none: LocalizedStringResource("ERROR", bundle: .module)
        case .pdf: LocalizedStringResource("Pdf", bundle: .module)
        case .photo: LocalizedStringResource("Photo", bundle: .module)
        case .rule: LocalizedStringResource("Rules", bundle: .module)
        case .search: LocalizedStringResource("Search", bundle: .module)
        case .setting: LocalizedStringResource("Settings", bundle: .module)
        case .space: LocalizedStringResource("Space", bundle: .module)
        case .table: LocalizedStringResource("Table", bundle: .module)
        case .value: LocalizedStringResource("Character", bundle: .module)
        case .weather: LocalizedStringResource("Weather", bundle: .module)
        }
    }

    public var title: String {
        String(localized: localizedTitle)
    }
    
    public var icon: String {
        switch self {
        case .adventure: "wand.and.stars"
        case .audio: "music.note.list"
        case .dice: "dice"
        case .editor: "pencil"
        case .game: "person.2"
        case .generator: "apple.intelligence"
        case .map: "map"
        case .none: "warning"
        case .pdf: "apple.books.pages"
        case .photo: "photo.on.rectangle.angled"
        case .rule: "book.closed"
        case .search: "magnifyingglass"
        case .setting: "gear"
        case .space: "view.3d"
        case .table: "tablecells.fill"
        case .value: "list.bullet.rectangle"
        case .weather: "cloud.bolt.rain"
        }
    }

    public var linkWindowId: String {
        switch self {
        case .adventure: "AdventureLink"
        case .audio: "AudioLink"
        case .dice: "DiceLink"
        case .editor: "NoWindow"
        case .game: "NoWindow"
        case .generator: "NoWindow"
        case .map: "MapLink"
        case .none: "NoWindow"
        case .pdf: "PdfLink"
        case .photo: "PhotoLink"
        case .rule: "RuleLink"
        case .search: "NoWindow"
        case .setting: "NoWindow"
        case .space: "SpaceLink"
        case .table: "TableLink"
        case .value: "ValueLink"
        case .weather: "WeatherLink"
        }
    }
    
    public var viewerWindowId: String {
        linkWindowId + "Viewer"
    }

    public var linkAltWindowId: String {
        linkWindowId + "Alt"
    }

    /// SceneId of the window that owns this module's UI on the current platform.
    ///
    /// Mirrors `AppModel.navigator(for:)` so callers can open the right window before sending a route.
    /// - macOS: only `.game` lives in the Game window; `.search` and `.setting` have their own
    ///   windows; every other module surfaces in the Editor window.
    /// - visionOS: editor modules live in `.editor`; `.setting` stays inside the Game window.
    /// - iOS / iPadOS / tvOS: everything lives in the Game window.
    public var sceneId: SceneId {
#if os(macOS)
        switch self {
        case .game, .none: return .game
        case .search: return .search
        case .setting: return .settings
        default: return .editor
        }
#elseif os(visionOS)
        switch self {
        case .game, .adventure, .value, .search, .setting, .generator, .none: return .game
        default: return .editor
        }
#else
        return .game
#endif
    }

    public var color: Color {
        switch self {
        case .adventure: Color("AdventureBackground", bundle: .module)
        case .audio: Color("AudioBackground", bundle: .module)
        case .dice: Color("DiceBackground", bundle: .module)
        case .editor: .blue
        case .game: .blue
        case .generator: .blue
        case .map: Color("MapBackground", bundle: .module)
        case .none: .blue
        case .pdf: Color("PdfBackground", bundle: .module)
        case .photo: Color("PhotoBackground", bundle: .module)
        case .rule: .indigo
        case .search: .blue
        case .setting: .blue
        case .space: Color("SpaceBackground", bundle: .module)
        case .table: Color("TableBackground", bundle: .module)
        case .value: Color("CharacterBackground", bundle: .module)
        case .weather: Color("WeatherBackground", bundle: .module)
        }
    }
    
    public var tint: Color {
        switch self {
        case .adventure: Color("AdventureTint", bundle: .module)
        case .audio: Color("AudioTint", bundle: .module)
        case .dice: Color("DiceTint", bundle: .module)
        case .editor: .blue
        case .game: .blue
        case .generator: .blue
        case .map: Color("MapTint", bundle: .module)
        case .none: .blue
        case .pdf: Color("PdfTint", bundle: .module)
        case .photo: Color("PhotoTint", bundle: .module)
        case .rule: .indigo
        case .space: Color("SpaceTint", bundle: .module)
        case .search: .blue
        case .setting: .blue
        case .table: Color("TableTint", bundle: .module)
        case .value: Color("CharacterTint", bundle: .module)
        case .weather: Color("WeatherTint", bundle: .module)
        }
    }
}
