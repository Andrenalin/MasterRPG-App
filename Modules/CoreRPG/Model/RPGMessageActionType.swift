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
    case generatedValue = 16

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
        case .generatedValue:
            return "GeneratedValue"
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
