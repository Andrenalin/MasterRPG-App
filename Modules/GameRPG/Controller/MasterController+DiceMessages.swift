// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

// MARK: - Dice Messages

extension MasterController {
    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else { return nil }
        if model.senderType == .observer {
            guard model.purpose == .assetRequest,
                  model.data.data == nil,
                  model.type == .reveal || model.type == .store
            else { return nil }
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal, .store:
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            guard root.gameModel.gameControl.features.dicePlayers else { return nil }
            guard model.sender.isMaster || model.isPlayerDiceGroupEvent else { return nil }
            if let diceResult = DiceResultModel.decodeData(of: model.data.data) {
                root.battleRoundController.recordDiceResult(
                    diceResult,
                    senderId: model.sender.id,
                    isMaster: model.sender.isMaster
                )
            }
            let (_, resultCategory) = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: model.senderName,
                supporterTier: model.sender.supporterTier,
                isGameMaster: model.sender.isMaster
            )
            if let diceResult = DiceResultModel.decodeData(of: model.data.data),
               let resultCategory {
                root.tableRoot.tableGameControllable.addResult(
                    resultCategory,
                    diceResult: diceResult
                )
            }
        }
        return nil
    }
}
