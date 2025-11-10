// @copyright André Trettin

import AndrenalinKit
import AppIntents
import SwiftUI

enum NavigationOption: String, Hashable, Identifiable, CaseIterable, AppEnum {
    case adventure
    case audio
    case character
    case dice
    case game
    case map
    case pdf
    case photo
    case search
    case space
    case table
    case weather
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Navigation Option", table: "AppIntents"),
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
        NavigationOption.table: DisplayRepresentation(
            title: "Table",
            image: .init(systemName: "tablecells.fill")
        ),
        NavigationOption.search: DisplayRepresentation(
            title: "Search",
            image: .init(systemName: "magnifyingglass")
        ),
        NavigationOption.space: DisplayRepresentation(
            title: "Space",
            image: .init(systemName: "view.3d")
        ),
        NavigationOption.weather: DisplayRepresentation(
            title: "Weather",
            image: .init(systemName: "cloud.bolt.rain")
        ),
    ]
    
    var id: String { rawValue }
    
    var name: LocalizedStringResource {
        switch self {
            case .photo: "Photo"
            case .map: "Map"
            case .table: "Table"
            case .adventure: "Adventure"
            case .dice: "Dice"
            case .weather: "Weather"
            case .game: "Game"
            case .character: "Character"
            case .audio: "Audio"
            case .pdf: "Pdf"
            case .space: "Space"
            case .search: "Search"
        }
    }
    
    var symbolName: String {
        switch self {
            case .game: "person.2"
            case .photo: "photo.on.rectangle.angled"
            case .character: "list.bullet.rectangle"
            case .adventure: "wand.and.stars"
            case .map: "map"
            case .table: "tablecells.fill"
            case .weather: "cloud.bolt.rain"
            case .dice: "dice"
            case .audio: "music.note.list"
            case .pdf: "books.vertical"
            case .space: "view.3d"
            case .search: "magnifyingglass"
        }
    }
}
