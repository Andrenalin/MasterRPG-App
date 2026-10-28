// @copyright André Trettin

import CoreRPG
import AppIntents
import SwiftUI

/// The sections Siri and Shortcuts can navigate to. The generator is left out on purpose: it has no
/// list of its own, its views are inlined where they are needed. See CODE_AUDIT_Since_3.0.1 §5.3.
enum NavigationOption: String, CaseIterable, AppEnum {
    case adventure
    case audio
    case character
    case dice
    case game
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
    
    var module: NetworkModules {
        switch self {
        case .adventure: .adventure
        case .audio: .audio
        case .character: .value
        case .dice: .dice
        case .game: .game
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
