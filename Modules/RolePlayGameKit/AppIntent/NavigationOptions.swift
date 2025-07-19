import AppIntents
import CoreRPG
import SwiftUI

enum NavigationOption: String, Hashable, Identifiable, CaseIterable, AppEnum {
    case game
    case adventure
    case character
    case pdf
    case table
    case map
    case photo
    case audio
    case space
    case weather
    case dice
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Navigation Option", table: "AppIntents"),
            numericFormat: "\(placeholder: .int) navigation options"
        )
    }
    
    static let caseDisplayRepresentations = [
        NavigationOption.game: DisplayRepresentation(
            title: "Game",
            image: .init(systemName: "person.2.wave.2")
        ),
        NavigationOption.adventure: DisplayRepresentation(
            title: "Adventure",
            image: .init(systemName: "wand.and.stars")
        ),
        NavigationOption.character: DisplayRepresentation(
            title: "Character",
            image: .init(systemName: "list.bullet.rectangle")
        ),
        NavigationOption.pdf: DisplayRepresentation(
            title: "Pdf",
            image: .init(systemName: "books.vertical")
        ),
        NavigationOption.table: DisplayRepresentation(
            title: "Table",
            image: .init(systemName: "tablecells.fill")
        ),
        NavigationOption.map: DisplayRepresentation(
            title: "Map",
            image: .init(systemName: "map")
        ),
        NavigationOption.photo: DisplayRepresentation(
            title: "Photo",
            image: .init(systemName: "photo.on.rectangle.angled")
        ),
        NavigationOption.audio: DisplayRepresentation(
            title: "Audio",
            image: .init(systemName: "music.note.list")
        ),
        NavigationOption.space: DisplayRepresentation(
            title: "Space",
            image: .init(systemName: "view.3d")
        ),
        NavigationOption.weather: DisplayRepresentation(
            title: "Weather",
            image: .init(systemName: "cloud.bolt.rain")
        ),
        NavigationOption.dice: DisplayRepresentation(
            title: "Dice",
            image: .init(systemName: "dice")
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
        }
    }
    
    var symbolName: String {
        switch self {
        case .game: "person.2.wave.2"
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
        }
    }
}
