// @copyright André Trettin

import Foundation
import SwiftUI

public protocol CategoryTextRepresentable: Equatable, Hashable, Identifiable {
    var title: String { get }
}

public enum ItemListCategory: Int, Equatable, Codable, CaseIterable, CategoryTextRepresentable, Sendable {
    case all = 0
    case hide = 1

    // structure
    case folder = 2
    case drop = 3
    case entry = 4

    // collections
    case album = 7000
    case bookshelf = 7001
    case collection = 7004
    case diceBag = 7003
    case playlist = 3001
    case models = 7002

    // Module names
    case adventure = 1000
    case audio = 1001
    case dice = 1002
    case game = 1003
    case map = 1004
    case pdf = 1005
    case photo = 1006
    case table = 1007
    case value = 1008
    case weather = 1009

    // Adventures
    case scenario = 2001
    case campaign = 2002
    case rules = 2003
    case supplement = 2004

    // Audio
    case music = 3000
    case sound = 3002

    // Map
    case dungeon = 4000
    case building = 4001

    // Tables
    case generator = 5001
    case loot = 5002

    // Values
    case item = 6000
    case character = 6001
    case gameMaster = 6002
    case monster = 6003


    public var id: Int {
        rawValue
    }

    public var isCollection: Bool {
        switch self {
        case .album, .collection, .diceBag, .playlist, .bookshelf, .models: true
            default: false
        }
    }

    public var localizedTitle: LocalizedStringResource {
        switch self {
            case .all: LocalizedStringResource("All", bundle: .module)
            case .hide: LocalizedStringResource("Hide", bundle: .module)

            case .drop: LocalizedStringResource("Drop", bundle: .module)
            case .folder: LocalizedStringResource("Folder", bundle: .module)
            case .entry: LocalizedStringResource("Entry", bundle: .module)

            case .album: LocalizedStringResource("Album", bundle: .module)
            case .bookshelf: LocalizedStringResource("Bookshelf", bundle: .module)
            case .collection: LocalizedStringResource("Collection", bundle: .module)
            case .diceBag: LocalizedStringResource("Dice Bag", bundle: .module)
            case .models: LocalizedStringResource("Models", bundle: .module)
            case .playlist: LocalizedStringResource("Playlist", bundle: .module)

            case .adventure: LocalizedStringResource("Adventure", bundle: .module)
            case .audio: LocalizedStringResource("Audio", bundle: .module)
            case .building: LocalizedStringResource("Building", bundle: .module)
            case .campaign: LocalizedStringResource("Campaign", bundle: .module)
            case .character: LocalizedStringResource("Character", bundle: .module)
            case .dice: LocalizedStringResource("Dice", bundle: .module)
            case .dungeon: LocalizedStringResource("Dungeon", bundle: .module)
            case .game: LocalizedStringResource("Game", bundle: .module)
            case .gameMaster: LocalizedStringResource("Game Master", bundle: .module)
            case .generator: LocalizedStringResource("Generator", bundle: .module)
            case .item: LocalizedStringResource("Item", bundle: .module)
            case .loot: LocalizedStringResource("Loot", bundle: .module)
            case .map: LocalizedStringResource("Map", bundle: .module)
            case .monster: LocalizedStringResource("Monster", bundle: .module)
            case .music: LocalizedStringResource("Music", bundle: .module)
            case .pdf: LocalizedStringResource("Pdf", bundle: .module)
            case .photo: LocalizedStringResource("Photo", bundle: .module)
            case .rules: LocalizedStringResource("Rules", bundle: .module)
            case .scenario: LocalizedStringResource("Scenario", bundle: .module)
            case .sound: LocalizedStringResource("Sound", bundle: .module)
            case .supplement: LocalizedStringResource("Supplement", bundle: .module)
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
            case .all: "list.bullet"

            case .drop: "square.and.arrow.down.on.square"
            case .folder: "folder"
            case .entry: "text.document"

            case .album: "rectangle.stack"
            case .bookshelf: "books.vertical"
            case .collection: "tray.2"
            case .diceBag: "bag"
            case .models: "square.3.layers.3d.down.right"
            case .playlist:"play.square.stack"

            case .game: "person.2"
            case .photo: "photo.on.rectangle.angled"
            case .value: "list.bullet.rectangle"
            case .adventure: "wand.and.stars"
            case .map: "map"
            case .table: "tablecells.fill"
            case .weather: "cloud.bolt.rain"
            case .dice: "dice"
            case .audio: "music.note.list"
            case .pdf: "apple.books.pages"

            case .sound: "waveform"
            case .music: "music.note.list"

            default: "exclamationmark.triangle"
        }
    }
}
