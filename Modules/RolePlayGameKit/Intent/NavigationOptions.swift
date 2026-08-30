// @copyright André Trettin

import CoreRPG
import AppIntents
import SwiftUI

enum NavigationOption: String, Hashable, Identifiable, CaseIterable, AppEnum {
    case adventure
    case audio
    case character
    case dice
    case game
    case generator
    case map
    case pdf
    case photo
    case rule
    case search
    case space
    case table
    case weather
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: "Navigation Option",
            numericFormat: "\(placeholder: .int) navigation options"
        )
    }
    
    static let caseDisplayRepresentations = [
        NavigationOption.adventure: DisplayRepresentation(
            title: "Adventure",
            image: .init(systemName: "wand.and.stars")
        ),
        NavigationOption.audio: DisplayRepresentation(
            title: "Audio",
            image: .init(systemName: "music.note.list")
        ),
        NavigationOption.character: DisplayRepresentation(
            title: "Character",
            image: .init(systemName: "list.bullet.rectangle")
        ),
        NavigationOption.dice: DisplayRepresentation(
            title: "Dice",
            image: .init(systemName: "dice")
        ),
        NavigationOption.game: DisplayRepresentation(
            title: "Game",
            image: .init(systemName: "person.2")
        ),
        NavigationOption.generator: DisplayRepresentation(
            title: "Generator",
            image: .init(systemName: "apple.intelligence")
        ),
        NavigationOption.map: DisplayRepresentation(
            title: "Map",
            image: .init(systemName: "map")
        ),
        NavigationOption.pdf: DisplayRepresentation(
            title: "Pdf",
            image: .init(systemName: "books.vertical")
        ),
        NavigationOption.photo: DisplayRepresentation(
            title: "Photo",
            image: .init(systemName: "photo.on.rectangle.angled")
        ),
        NavigationOption.rule: DisplayRepresentation(
            title: "Rules",
            image: .init(systemName: "book.closed")
        ),
        NavigationOption.search: DisplayRepresentation(
            title: "Search",
            image: .init(systemName: "magnifyingglass")
        ),
        NavigationOption.space: DisplayRepresentation(
            title: "Space",
            image: .init(systemName: "view.3d")
        ),
        NavigationOption.table: DisplayRepresentation(
            title: "Table",
            image: .init(systemName: "tablecells.fill")
        ),
        NavigationOption.weather: DisplayRepresentation(
            title: "Weather",
            image: .init(systemName: "cloud.bolt.rain")
        ),
    ]
    
    var id: String { rawValue }
    
    var name: LocalizedStringResource {
        switch self {
        case .adventure: "Adventure"
        case .audio: "Audio"
        case .dice: "Dice"
        case .character: "Character"
        case .game: "Game"
        case .generator: "Generator"
        case .map: "Map"
        case .pdf: "Pdf"
        case .photo: "Photo"
        case .rule: "Rules"
        case .search: "Search"
        case .space: "Space"
        case .table: "Table"
        case .weather: "Weather"
        }
    }
    
    var symbolName: String {
        switch self {
        case .adventure: "wand.and.stars"
        case .audio: "music.note.list"
        case .character: "list.bullet.rectangle"
        case .dice: "dice"
        case .game: "person.2"
        case .generator: "apple.intelligence"
        case .map: "map"
        case .pdf: "books.vertical"
        case .photo: "photo.on.rectangle.angled"
        case .rule: "book.closed"
        case .search: "magnifyingglass"
        case .space: "view.3d"
        case .table: "tablecells.fill"
        case .weather: "cloud.bolt.rain"
        }
    }

    var module: NetworkModules {
        switch self {
        case .adventure: .adventure
        case .audio: .audio
        case .character: .value
        case .dice: .dice
        case .game: .game
        case .generator: .generator
        case .map: .map
        case .pdf: .pdf
        case .photo: .photo
        case .rule: .rule
        case .search: .search
        case .space: .space
        case .table: .table
        case .weather: .weather
        }
    }
}
