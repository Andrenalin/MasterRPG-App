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
    
    public var token: String {
        switch self {
        case .photo: "PHOTOS"
        case .map: "MAPS"
        case .table: "TABLES"
        case .adventure: "ADVENTURES"
        case .dice: "DICE"
        case .weather: "WEATHERS"
        case .game: "GAME"
        case .value: "VALUES"
        case .audio: "AUDIOS"
        case .pdf: "PDFS"
        case .space: "SPACES"
        case .setting: "SETTINGS"
        case .editor: "EDITOR"
        case .none: "ERROR"
        }
    }

    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .photo: "Photo"
        case .map: "Map"
        case .table: "Table"
        case .adventure: "Adventure"
        case .dice: "Dice"
        case .weather: "Weather"
        case .game: "Game"
        case .value: "Character"
        case .audio: "Audio"
        case .pdf: "Pdf"
        case .space: "Space"
        case .setting: "Settings"
        case .editor: "Editors"
        case .none: "ERROR"
        }
    }

    public var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    public var icon: String {
        switch self {
        case .game: "person.2"
        case .photo: "photo.on.rectangle.angled"
        case .value: "list.bullet.rectangle"
        case .adventure: "wand.and.stars"
        case .map: "map"
        case .table: "tablecells.fill"
        case .weather: "cloud.bolt.rain"
        case .dice: "dice"
        case .audio: "music.note.list"
        case .pdf: "books.vertical"
        case .space: "view.3d"
        case .setting: "gear"
        case .editor: "pencil"
        case .none: "warning"
        }
    }

    public var linkWindowId: String {
        switch self {
        case .photo: "PhotoLink"
        case .value: "ValueLink"
        case .adventure: "AdventureLink"
        case .map: "MapLink"
        case .table: "TableLink"
        case .weather: "WeatherLink"
        case .dice: "DiceLink"
        case .audio: "AudioLink"
        case .pdf: "PdfLink"
        case .space: "SpaceLink"
        case .none: "NoWindow"
        case .game: "NoWindow"
        case .setting: "NoWindow"
        case .editor: "NoWindow"
        }
    }
    
    public var linkAltWindowId: String {
        linkWindowId + "Alt"
    }
    
    public var color: Color {
        switch self {
        case .adventure: .blue
        case .audio: .cyan
        case .dice: .purple
        case .editor: .gray
        case .map: .indigo
        case .none: .clear
        case .game: .pink
        case .pdf: .red
        case .photo: .yellow
        case .space: .brown
        case .setting: .mint
        case .table: .green
        case .value: .teal
        case .weather: .orange
        }
    }
    
    public var endColor: Color {
        switch self {
        case .adventure: .green
        case .audio: .red
        case .dice: .green
        case .editor: .green
        case .map: .green
        case .none: .black
        case .game: .yellow
        case .pdf: .yellow
        case .photo: .green
        case .space: .green
        case .setting: .green
        case .table: .red
        case .value: .red
        case .weather: .green
        }
    }
}
