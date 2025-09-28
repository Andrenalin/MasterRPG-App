// @copyright André Trettin

import CoreRPG
import Combine
import Foundation
import GroupActivities
import SwiftUI


@MainActor @Observable
final class GameRootModel: Sendable {
    var gameConfig: GameConfigModel = .empty
    
    var startGameTime = Date()
    
    var selectedCharacter: UUID?
    var selectedGameMaster: UUID?
    public var selectedAdventure: UUID?
    
    var playerGameStarted: Bool = false
    
    var logData: [Int: LogGameModel] = [:]
    var logs: [Int] = []
    var playerScreens: [UUID: Data] = [:]
    var attachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
    var metaDataAttachments: [NetworkModules: UUID] = [:]
    
    var masterController: MasterController?
    var playerController: PlayerController?
    
    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
        if let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) {
            gameConfig.players[index] = playerModel
            var model = sharingModel
            model.show = gameConfig.controls[index].show
            gameConfig.controls[index] = model
            return false
        } else {
            gameConfig.players.append(playerModel)
            gameConfig.controls.append(sharingModel)
            return true
        }
    }
    
    func add(playerId: UUID, sharingModel: SharingControlModel) {
        if let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) {
            gameConfig.controls[index] = sharingModel
        } else {
            gameConfig.controls.append(sharingModel)
        }
    }
    
    func remove(playerId: UUID) -> Bool {
        guard let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) else { return false }
        gameConfig.players.remove(at: index)
        gameConfig.controls.remove(at: index)
        return true
    }
    
    func reset(gameConfig: GameConfigModel) {
        self.gameConfig = gameConfig
    }
    
    func reset(controls: [SharingControlModel]) {
        gameConfig.controls = controls
    }
    
    func reset(master: MasterGameModel) {
        gameConfig.master = master
    }

    func reset(playerId: UUID, player: PlayerGameModel, players: [PlayerGameModel]) {
        var updatedPlayers = players
        if !updatedPlayers.contains(where: { $0.id == playerId }) {
            updatedPlayers.append(player)
        }
        gameConfig.players = updatedPlayers
    }

    func reset(features: GameFeatureModel) {
        gameConfig.features = features
    }
}
