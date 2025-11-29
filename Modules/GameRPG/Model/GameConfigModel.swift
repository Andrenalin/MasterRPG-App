// @copyright André Trettin

import CoreRPG
import Foundation

enum GameState: Equatable, Codable, Sendable {
    case stopped
    case prepare
    case started
}

struct GameConfigModel: Equatable, Identifiable, Codable, Sendable {
    var id: UUID
    var state: GameState
    var master: MasterGameModel
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel = GameFeatureModel()
    
    var type: GameType {
        if master.id == id {
            return master.type
        } else {
            return players.first(where: { $0.id == id })?.type ?? .notSet
        }
    }
    
    var name: String {
        if master.id == id {
            return master.name
        } else {
            return players.first(where: { $0.id == id })?.name ?? ""
        }
    }
    
    var isMaster: Bool {
        master.id == id
    }

    var player: PlayerGameModel {
        players.first(where: { $0.id == id }) ?? .empty
    }
        
    static let empty = GameConfigModel(id: UUID(), state: .stopped, master: .empty, players: [], controls: [])
}
