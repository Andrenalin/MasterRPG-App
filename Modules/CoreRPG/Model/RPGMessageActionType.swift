// @copyright André Trettin

import Foundation

public enum RPGMessageActionType: Int, Codable, Hashable, Sendable {
    case store = 10
    case show = 20
    case ok = 200
    case screen = 300
    case failed = 400

    case generic = 1
    
    case playAudio = 2
    case audioList = 8
    case photoList = 11
    case spaceList = 12
    case pdfList = 13
    case valueUpdate = 15
    /// A Table-generated outcome the master pushes to a player (or every
    /// visible player) as a new Character value. See
    /// `TableGenerationRootView.send(to:)` (sender) and
    /// `PlayerController+Value.handleAddItem(_:)` (receiver).
    case addItem = 16
    /// How a photo shown while a map is on screen is presented: as a popover on the map, full
    /// screen or closed. Only the game master sends it; its payload is GameRPG's
    /// `MapPhotoPresentation`. See `MasterController+MapPhoto.swift` (sender) and
    /// `PlayerController+MapPhoto.swift` (receiver).
    case photoPresentation = 17
    /// The weather the game master shows on the 3D game table, or none. Only the game master
    /// sends it; its payload is GameRPG's `TableWeatherPresentation`. See
    /// `MasterController+TableWeather.swift` (sender) and `PlayerController+Weather.swift`
    /// (receiver).
    case tableWeather = 18

    case mapState = 3
    case mapPin = 4
    case battleRound = 14

    case spaceTransform = 9
}

extension RPGMessageActionType: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .ok:
            return "Ok"
        case .failed:
            return "Failed"
        case .generic:
            return "Generic"
        case .audioList:
            return "AudioList"
        case .photoList:
            return "PhotoList"
        case .spaceList:
            return "SpaceList"
        case .pdfList:
            return "PdfList"
        case .valueUpdate:
            return "ValueUpdate"
        case .addItem:
            return "AddItem"
        case .photoPresentation:
            return "PhotoPresentation"
        case .tableWeather:
            return "TableWeather"
        case .playAudio:
            return "PlayAudio"
        case .screen:
            return "Screen"
        case .store:
            return "Store"
        case .show:
            return "Show"
        case .mapState:
            return "MapState"
        case .mapPin:
            return "MapPin"
        case .battleRound:
            return "BattleRound"
        case .spaceTransform:
            return "SpaceTransform"
        }
    }
}
