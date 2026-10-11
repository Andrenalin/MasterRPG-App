// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation

@testable import GameRPG

extension GameNetworkModel {
    /// Test builder in the config/roster/control shape of the local game state: derives
    /// sender and master state the same way production senders do, so test scenarios stay
    /// expressed in the familiar form.
    init(
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        gameConfig: GameConfigModel,
        gameRoster: GameRosterModel = .empty,
        gameControl: GameControlModel = .empty,
        targetId: UUID? = nil,
        data: NetworkCodableDataType
    ) {
        let sender: GameSenderModel
        var masterState: GameMasterStateModel?
        if gameConfig.isMaster {
            sender = GameSenderModel(
                id: gameConfig.id,
                role: .master,
                name: gameConfig.master.name,
                characterId: nil,
                supporterTier: gameConfig.master.supporterTier
            )
            masterState = GameMasterStateModel(
                state: gameConfig.state,
                adventureId: gameConfig.master.adventureId,
                adventureTitle: gameConfig.master.adventureTitle,
                players: gameRoster.players,
                controls: gameControl.controls,
                features: gameControl.features
            )
        } else {
            let player = gameRoster.players.first(where: { $0.id == gameConfig.id })
            let role: GameType = if let type = player?.type, type != .notSet { type } else { .player }
            let name = if let playerName = player?.name, !playerName.isEmpty {
                playerName
            } else {
                "Player \(gameConfig.id.uuidString.prefix(8))"
            }
            sender = GameSenderModel(
                id: gameConfig.id,
                role: role,
                name: name,
                characterId: player?.characterId,
                supporterTier: player?.supporterTier ?? .none
            )
        }
        self.init(
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: gameConfig.master.id,
            sender: sender,
            masterState: masterState,
            targetId: targetId,
            data: data
        )
    }
}

extension MasterController {
    /// Binds a connection to the player it speaks for, the way the first message of that
    /// player does.
    @discardableResult
    func bind(connectionId: UUID, playerId: UUID, role: GameType = .player) -> Bool {
        store.model.playerRoutes.bind(
            asProxy ? .proxy(connectionId) : .direct(connectionId),
            to: GameSenderModel(id: playerId, role: role, name: "", characterId: nil)
        )
    }
}
#endif
