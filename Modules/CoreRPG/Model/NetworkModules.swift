// @copyright André Trettin

import Foundation
import SwiftUI

public enum NetworkModules: Int, Codable, Sendable, CaseIterable {
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
        case .adventure: "Adventure"
        case .audio: "Audio"
        case .dice: "Dice"
        case .editor: "Editors"
        case .game: "Game"
        case .generator: "Generator"
        case .map: "Map"
        case .none: "ERROR"
        case .pdf: "Pdf"
        case .photo: "Photo"
        case .search: "Search"
        case .setting: "Settings"
        case .space: "Space"
        case .table: "Table"
        case .value: "Character"
        case .weather: "Weather"
        }
    }

    public var title: String {
        String(localized: localizedTitle).localizedString
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
        case .search: "NoWindow"
        case .setting: "NoWindow"
        case .space: "SpaceLink"
        case .table: "TableLink"
        case .value: "ValueLink"
        case .weather: "WeatherLink"
        }
    }

    public var viewerkWindowId: String {
        linkWindowId + "Viewer"
    }

    public var linkAltWindowId: String {
        linkWindowId + "Alt"
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
        case .space: Color("SpaceTint", bundle: .module)
        case .search: .blue
        case .setting: .blue
        case .table: Color("TableTint", bundle: .module)
        case .value: Color("CharacterTint", bundle: .module)
        case .weather: Color("WeatherTint", bundle: .module)
        }
    }
}
