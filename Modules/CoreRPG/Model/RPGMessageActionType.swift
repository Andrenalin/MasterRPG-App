// @copyright André Trettin

import Foundation

/// What a game message does.
///
/// Wire format: the raw values travel in every envelope and decode strictly. A peer that does
/// not know a case cannot decode the envelope and drops it, with a decode error and no hint
/// about the version. Adding, removing or renumbering a case therefore changes the wire format:
/// bump `GameNetworkModel.currentVersion` with it (a peer of another version is refused with an
/// explicit "unsupported version" instead). `WireContractTests` pins the cases and the version
/// together so that neither changes alone. See CODE_AUDIT_Game_Shareplay §4.1.
public enum RPGMessageActionType: Int, Codable, Hashable, Sendable {
    case store = 10
    case show = 20
    case ok = 200
    /// Reserved: nothing sends it any more. The raw value stays so that an envelope of an older
    /// peer still decodes; the master does not admit it.
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
