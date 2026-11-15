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

// MARK: - Player messages

extension MasterController {
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        // Weather is immutable during a game. It is presented and requested via reveal messages
        // only; its one live message is the game master's lightning strike (`.generic`).
        if message.type == .weather, actionType == .generic {
            await sendLightning(message)
            return
        }
        guard message.type != .table, message.type != .weather else { return }
        // Character/Value updates have no general in-game protocol — the
        // player join handshake has its own exchange elsewhere, and the only
        // Value push a master can trigger here is `.addItem` (a Table-
        // generated outcome sent to a player as a new Character value).
        guard message.type != .value || actionType == .addItem else { return }
        if message.type == .dice,
           actionType == .generic,
           let diceResult = DiceResultModel.decodeData(of: message.data) {
            root.battleRoundController.recordDiceResult(
                diceResult,
                senderId: root.gameModel.gameConfig.id,
                isMaster: true
            )
        }
        if message.type == .audio, actionType == .playAudio {
            await requestAudioPlay(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.isValidSpaceTransform(message),
                  root.spaceRoot.gameControllable.gameModel.currentItemId == message.id
            else { return }
            let version = await root.spaceRoot.gameControllable.networkVersion(for: message.id)
            let canonical = NetworkCodableDataType(
                id: message.id,
                type: .space,
                version: version,
                data: message.data
            )
            await send(type: .update, subtype: .spaceTransform, updated: canonical, playerId: playerId)
            return
        }
        await send(type: .update, subtype: actionType, updated: message, playerId: playerId)
    }
}
