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

extension PlayerController {
    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = root.gameModel.gameControl.features
        guard (root.gameModel.gameConfig.id != model.sender.id) &&
                (features.diceMaster || !model.sender.isMaster) &&
                (features.dicePlayers || model.sender.isMaster)
        else {
            Logger.networking.debug("PlayerController: Dice update from \(model.sender.id, privacy: .public) ignored — self message or feature gate (diceMaster: \(features.diceMaster, privacy: .public), dicePlayers: \(features.dicePlayers, privacy: .public), senderIsMaster: \(model.sender.isMaster, privacy: .public))")
            // A group roll that this device does not apply is not a failure to report: every
            // player would answer every roll. Only a message addressed to this device is
            // answered. See CODE_AUDIT_Game_Shareplay §5.21.
            guard model.targetId == root.gameModel.gameConfig.id else { return nil }
            return response(for: model, isSuccess: false, requestData: false)
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
                return response(for: model, isSuccess: true, requestData: true)
            }
            return response(for: model, isSuccess: true, requestData: false)
        case .store:
            try await root.diceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: model.subType == .show)
            return response(for: model, isSuccess: true, requestData: false)
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
                    isGameMaster: model.sender.isMaster,
                    senderId: model.sender.id
                )
                break
            default:
                break
            }
        }
        return nil
    }
}
