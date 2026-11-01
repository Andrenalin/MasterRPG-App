// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import os.log

extension PlayerController {
    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = root.gameModel.gameControl.features
        guard (root.gameModel.gameConfig.id != model.sender.id) &&
                (features.diceMaster || !model.sender.isMaster) &&
                (features.dicePlayers || model.sender.isMaster)
        else {
            Logger.networking.debug("PlayerController: Dice update from \(model.sender.id, privacy: .public) ignored — self message or feature gate (diceMaster: \(features.diceMaster, privacy: .public), dicePlayers: \(features.dicePlayers, privacy: .public), senderIsMaster: \(model.sender.isMaster, privacy: .public))")
            return await response(for: model, isSuccess: false, requestData: false)
        }

        // Peers may contribute only a complete roll. Dice focus/visibility and
        // package commands remain master-authoritative.
        guard model.sender.isMaster || (model.isPlayerGroupEvent && model.isDiceRollEvent) else {
            Logger.networking.debug("PlayerController: Dice update from \(model.sender.id, privacy: .public) ignored — not a recognized player dice group event (role: \(String(describing: model.sender.role), privacy: .public), subType: \(model.subType.debugDescription, privacy: .public), hasData: \(model.data.data != nil, privacy: .public))")
            return nil
        }

        // A peer's roll is not authoritative here either: refuse values no dice can produce.
        // See CODE_AUDIT_23 §6.4.
        if !model.sender.isMaster, model.type == .update,
           let reported = DiceResultModel.decodeData(of: model.data.data), !reported.isPlausibleReport {
            Logger.networking.warning("PlayerController: Dice update from \(model.sender.id, privacy: .public) ignored — implausible roll")
            return nil
        }

        switch model.type {
        case .reveal:
            if try await !root.diceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            try await root.diceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: model.subType == .show)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .show, .store:
                try await root.diceRoot.diceGameControllable.updateGame(data: model.data, hide: model.subType == .store, focus: model.subType == .show)
            case .generic:
                root.gameModel.noteDiceRollSender(of: model)
                _ = root.diceRoot.diceGameControllable.addGameDiceResult(
                    data: model.data,
                    name: model.senderName,
                    supporterTier: model.sender.supporterTier,
                    isGameMaster: model.sender.isMaster
                )
                break
            default:
                break
            }
        }
        return nil
    }
}
