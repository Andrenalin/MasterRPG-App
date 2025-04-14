// @copyright André Trettin

import Foundation

public enum RPGMessageActionType: Int, Codable, Sendable {
    case store = 10
    case show = 20
    case ok = 200
    case screen = 300
    case failed = 400

    case generic = 1
    
    case playAudio = 2
    case audioList = 8

    case mapState = 3
    case mapPin = 4

    case photoSpace = 6
    
    case valueResult = 7
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
        case .photoSpace:
            return "PhotoSpace"
        case .valueResult:
            return "ValueResult"
        }
    }
}
