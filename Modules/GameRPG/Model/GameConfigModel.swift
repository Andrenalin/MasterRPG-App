// @copyright André Trettin

import CoreRPG
import Foundation

enum GameState: Equatable, Codable, Sendable {
    case stopped
    case prepare
    case started
}

// Structural config: identity and master info. Changes only at game start/stop.
struct GameConfigModel: Equatable, Identifiable, Codable, Sendable {
    var id: UUID
    var state: GameState
    var master: MasterGameModel

    var isMaster: Bool { master.id == id }

    func type(in roster: GameRosterModel) -> GameType {
        if isMaster { return master.type }
        return roster.players.first(where: { $0.id == id })?.type ?? .notSet
    }

    func name(in roster: GameRosterModel) -> String {
        if isMaster { return master.name }
        return roster.players.first(where: { $0.id == id })?.name ?? ""
    }

    func player(in roster: GameRosterModel) -> PlayerGameModel {
        roster.players.first(where: { $0.id == id }) ?? .empty
    }

    static let empty = GameConfigModel(id: UUID(), state: .stopped, master: .empty)
}

// Dynamic roster: players, sharing controls, and features. Changes on every join/leave.
struct GameRosterModel: Equatable, Codable, Sendable {
    var players: [PlayerGameModel] = []
    var controls: [SharingControlModel] = []
    var features: GameFeatureModel = GameFeatureModel()

    static let empty = GameRosterModel()
}
