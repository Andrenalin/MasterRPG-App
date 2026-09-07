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

// MARK: - Value Messages

extension MasterController {
    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.type == .update, model.subType == .valueUpdate {
            guard model.sender.role == .player,
                  model.purpose == .event,
                  model.effectiveAudience == .master,
                  let characterId = model.sender.characterId,
                  characterId == model.data.id,
                  // sender.characterId is otherwise self-declared, untrusted
                  // network input — every peer already sees every pin's
                  // characterId. See CODE_AUDIT_Game §6.1.
                  gameModel.isCharacterOwnershipAuthorized(senderId: model.sender.id, characterId: characterId),
                  let update = GameValueEntryUpdate.decodeData(of: model.data.data),
                  update.characterId == characterId,
                  root.gameModel.canApplyValueUpdate(
                      senderId: model.sender.id,
                      characterId: characterId,
                      entryId: update.entryId,
                      timestamp: model.timestamp
                  ),
                  root.characterRoot.valueGameControllable
                    .applyGameValueEntryUpdate(update) else {
                return nil
            }
            root.gameModel.recordValueUpdate(
                senderId: model.sender.id,
                characterId: characterId,
                entryId: update.entryId,
                timestamp: model.timestamp
            )
            return nil
        }

        // Character/Value messages have one normal-game purpose: synchronize
        // the selected Character when a player joins. Presentation, loot,
        // result, acknowledgement, and live-update variants are intentionally
        // unsupported until they get their own protocols.
        guard model.type == .update,
              model.subType == .store,
              model.senderType == .player,
              let characterId = model.sender.characterId,
              characterId == model.data.id,
              // The join handshake — binds this sender to characterId (or
              // confirms an existing binding). See CODE_AUDIT_Game §6.1.
              gameModel.bindCharacterOwnership(senderId: model.sender.id, characterId: characterId)
        else { return nil }

        if model.data.data == nil {
            let localVersion = await root.characterRoot.gameControllable.networkVersion(for: characterId)
            // Exact versions mean the master already owns this Character
            // package. Silence is the successful response; only a mismatch
            // asks the originating player for its potentially large package.
            guard localVersion != model.data.version else {
                root.mapRoot.mapGameControllable.setPlayerPin(
                    for: model.sender.id,
                    name: model.senderName,
                    characterId: characterId
                )
                await publishCurrentMapAfterPlayerPinChange()
                return nil
            }
            return model.data
        }

        try await root.characterRoot.valueGameControllable.updatePlayer(data: model.data)
        root.mapRoot.mapGameControllable.setPlayerPin(
            for: model.sender.id,
            name: model.senderName,
            characterId: characterId
        )
        await publishCurrentMapAfterPlayerPinChange()
        return nil
    }

    /// Character synchronization can finish after resetPlayers() created and
    /// broadcast a pin without its Character photo. Re-publish both the
    /// structural pin metadata and authoritative live state once the Character
    /// is known so every peer replaces that bootstrap copy immediately.
    private func publishCurrentMapAfterPlayerPinChange() async {
        guard let mapId = root.mapRoot.mapGameControllable.gameModel.currentItemId else {
            return
        }
        await send(
            type: .update,
            subtype: .generic,
            updated: await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
        )
        await send(
            type: .update,
            subtype: .mapState,
            updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId)
        )
    }
}
