// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// MARK: - Dice Messages

extension MasterController {
    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else { return nil }
        if model.senderType == .observer {
            guard model.isAssetRequest else { return nil }
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal, .store:
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            guard root.gameModel.gameControl.features.dicePlayers else {
                Logger.networking.debug("MasterController: Dice update from \(model.sender.id, privacy: .public) ignored — dicePlayers feature is off")
                return nil
            }
            guard model.sender.isMaster || (model.isPlayerGroupEvent && model.isDiceRollEvent) else {
                Logger.networking.debug("MasterController: Dice update from \(model.sender.id, privacy: .public) ignored — not a recognized player dice group event (role: \(String(describing: model.sender.role), privacy: .public), subType: \(model.subType.debugDescription, privacy: .public), hasData: \(model.data.data != nil, privacy: .public))")
                return nil
            }
            // A player's report is not authoritative: refuse values no dice can produce.
            // See CODE_AUDIT_15 §5.9.
            if !model.sender.isMaster, let reported = DiceResultModel.decodeData(of: model.data.data), !reported.isPlausibleReport {
                Logger.networking.warning("MasterController: Dice update from \(model.sender.id, privacy: .public) ignored — implausible roll")
                return nil
            }
            if let diceResult = DiceResultModel.decodeData(of: model.data.data) {
                root.battleRoundController.recordDiceResult(
                    diceResult,
                    senderId: model.sender.id,
                    isMaster: model.sender.isMaster
                )
            }
            root.gameModel.noteDiceRollSender(of: model)
            let (_, resultCategory) = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: model.senderName,
                supporterTier: model.sender.supporterTier,
                isGameMaster: model.sender.isMaster,
                senderId: model.sender.id
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
