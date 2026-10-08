// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import os.log

extension PlayerController {
    func handleValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard root.gameModel.gameType != .proxy else { return try await handleProxyValue(model) }
        if model.subType == .addItem {
            return await handleAddItem(model)
        }
        if model.sender.isMaster,
           model.type == .update,
           model.subType == .failed,
           model.data.type == .value,
           let characterId = root.gameModel.gamePlayer.characterId,
           characterId == model.data.id {
            // The master failed to import this player's Character package
            // (see MasterController+ValueMessages.swift). `hasSendPlayer` was
            // already latched true when the original reference went out;
            // clear it so the existing `scheduleSendCharacter()` triggers
            // retry `sendCharacter()` instead of the handshake staying wedged
            // for the rest of the session. See CODE_AUDIT_Network §5.24.
            // Retried with a growing delay and only a few times per Character version: every
            // later master message used to announce the Character again, and each announcement
            // ended in another full upload of a package the master cannot import.
            // See CODE_AUDIT_21 §5.5.
            if gameModel.recordCharacterRejection(version: model.data.version) {
                Logger.networking.error("PlayerController: Master failed to import Character \(characterId, privacy: .private) \(PlayerControllerModel.maximumCharacterRejections, privacy: .public) times; no longer sending it")
                let name = root.characterRoot.itemControllable.nameSync(itemId: characterId)
                root.logGameController.addNote(String(
                    localized: "The game master's device did not accept the Character \"\(name)\".",
                    bundle: .module
                ))
            } else {
                Logger.networking.error("PlayerController: Master failed to import Character \(characterId, privacy: .private); will retry")
            }
            return nil
        }
        // A normal player accepts only the master's targeted response to the
        // join announcement. No Value reveal, result, loot, or live update is
        // processed during the game.
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .store,
              model.data.data == nil,
              let characterId = root.gameModel.gamePlayer.characterId,
              characterId == model.data.id
        else { return nil }

        try Task.checkCancellation()
        let package = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        try Task.checkCancellation()
        // Character packages can be large, but only the game master consumes
        // them. Keep them off the SharePlay Journal and away from local proxy
        // clients; SharePlay peers may see the Messenger message and ignore it.
        await send(
            type: .update,
            subType: .store,
            updated: package,
            useJournal: false,
            relayToProxyClients: false
        )
        return nil
    }

    /// Adds a Table-generated outcome the master pushed to this player as a
    /// new value nested under the player's own Character — via
    /// `GameController.addItem(sheet:characterId:forceSave:)`, which (unlike
    /// `TableGenerationController`'s local Save path, see
    /// `TableGenerationRootView.send(to:)` for the sender side) groups the
    /// new value directly onto `characterId` rather than leaving it a
    /// disconnected top-level value. Forces persistence: this fires
    /// mid-game, while `isGameMode` is true, and a default (memory-only)
    /// save would otherwise vanish on next launch — see
    /// `ItemControllable.replace(model:isInsert:forceSave:)`.
    private func handleAddItem(_ model: GameNetworkModel) async -> GameNetworkModel? {
        guard model.sender.isMaster,
              model.type == .update,
              let characterId = root.gameModel.gamePlayer.characterId,
              let payload = SheetItemTransfer.decodeData(of: model.data.data)
        else { return nil }
        _ = await root.characterRoot.valueGameControllable.addItem(
            sheet: payload.makeSheetModel(),
            characterId: characterId,
            forceSave: true
        )
        return nil
    }
}
