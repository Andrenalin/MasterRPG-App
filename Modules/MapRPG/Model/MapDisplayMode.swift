// @copyright André Trettin

import Foundation

enum MapDisplayMode: Int, Identifiable, Equatable, Hashable, CaseIterable {
    case master = 0
    case player = 1
    case reader = 2

    var id: Int {
        rawValue
    }

    var text: String {
        switch self {
        case .master:
            return "Master"
        case .player:
            return "Player"
        case .reader:
            return "Reader"
        }
    }
}

