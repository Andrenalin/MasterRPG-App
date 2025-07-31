// @copyright André Trettin

import Foundation
import SwiftUI

public enum ItemListCategory: Int, Equatable, Codable, CaseIterable, CategoryTextRepresentable {
    case all = 0
    case hide = 1

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
    case playlist = 3001
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

    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .hide: "Hide"

        case .adventure: "Adventure"
        case .audio:"Audio"
        case .building:"Building"
        case .campaign:"Campaign"
        case .character:"Character"
        case .dice:"Dice"
        case .dungeon:"Dungeon"
        case .game:"Game"
        case .gameMaster:"Game Master"
        case .generator:"Generator"
        case .item:"Item"
        case .loot:"Loot"
        case .map:"Map"
        case .monster:"Monster"
        case .music:"Music"
        case .pdf:"Pdf"
        case .photo:"Photo"            
        case .playlist:"Playlist"
        case .rules:"Rules"
        case .scenario:"Scenario"
        case .sound:"Sound"
        case .supplement:"Supplement"
        case .table:"Table"
        case .value:"Character"
        case .weather:"Weather"
        }
    }
    
    public var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    public var icon: String {
        switch self {
        case .all: "list.bullet"
        case .hide: "eye.slash"
            
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
        default: "exclamationmark.triangle"
        }
    }

}
