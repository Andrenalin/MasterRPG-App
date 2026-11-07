// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import CharacterRPG
import MapRPG

// MARK: - Value Messages

extension MasterController {
    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.type == .update, model.subType == .valueUpdate {
            guard model.sender.role == .player,
                  let characterId = model.sender.characterId,
                  characterId == model.data.id
            else { return nil }

            // sender.characterId is otherwise self-declared, untrusted
            // network input — every peer already sees every pin's
            // characterId. See CODE_AUDIT_Game §6.1.
            guard gameModel.isCharacterOwnershipAuthorized(senderId: model.sender.id, characterId: characterId) else {
                // The update can legitimately race this same sender's own
                // join handshake (`.store`, below) across a mixed
                // proxy/SharePlay/LAN transport with no cross-message
                // ordering guarantee. Hold it so the handshake can replay it
                // once the binding lands, instead of silently dropping a
                // valid edit. See CODE_AUDIT_Network §5.18.
                gameModel.deferValueUpdateAwaitingOwnership(model)
                return nil
            }
            applyValueUpdate(model, characterId: characterId)
            return nil
        }

        // A player's companion Character, announced and sent like its own Character.
        if model.type == .update,
           model.subType == .store,
           model.senderType == .player,
           let companionId = companionCharacterId(of: model) {
            return try await handleCompanionStore(model, characterId: companionId)
        }

        // Character/Value messages have one normal-game purpose: synchronize
        // the selected Character when a player joins. Presentation, loot,
        // result, acknowledgement, and live-update variants are intentionally
        // unsupported until they get their own protocols.
        guard model.type == .update,
              model.subType == .store,
              model.senderType == .player,
              let characterId = model.sender.characterId,
              characterId == model.data.id
        else { return nil }
        // The join handshake — binds this sender to characterId (or
        // confirms an existing binding). See CODE_AUDIT_Game §6.1.
        guard gameModel.bindCharacterOwnership(senderId: model.sender.id, characterId: characterId) else {
            // Another sender plays this Character. The player is told, so it can clear its
            // "sent" flag instead of waiting for a pin that never comes. See
            // CODE_AUDIT_Audio2 §5.2.
            await send(
                type: .update,
                subtype: .failed,
                updated: NetworkCodableDataType(id: characterId, type: .value, version: model.data.version, data: nil),
                playerId: model.sender.id
            )
            return nil
        }

        // The binding just landed — replay any `.valueUpdate` this same
        // sender sent before it, which was held rather than dropped. See
        // CODE_AUDIT_Network §5.18.
        for pendingUpdate in gameModel.takePendingValueUpdates(senderId: model.sender.id) {
            applyValueUpdate(pendingUpdate, characterId: characterId)
        }

        if model.data.data == nil {
            // Silence is the successful response; only a version mismatch asks the originating
            // player for its potentially large package.
            guard await isCharacterOutOfDate(model, characterId: characterId) else {
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

        // INTENDED (CODE_AUDIT_17 §6.1, won't fix): a player may overwrite its own existing
        // Character on the master to update values; connections are already gated (PIN /
        // GM-approved / SharePlay call), so do not restrict the primary id here.
        guard await importPeerCharacter(model, characterId: characterId) else { return nil }
        root.mapRoot.mapGameControllable.setPlayerPin(
            for: model.sender.id,
            name: model.senderName,
            characterId: characterId
        )
        await publishCurrentMapAfterPlayerPinChange()
        return nil
    }

    /// The Character of a `.store` message when it is one of the sender's companions (its
    /// roster entry, refreshed from this very message) and nobody plays it as their own.
    private func companionCharacterId(of model: GameNetworkModel) -> UUID? {
        let characterId = model.data.id
        guard model.data.type == .value,
              characterId != model.sender.characterId,
              let player = root.gameModel.gameRoster.players.first(where: { $0.id == model.sender.id }),
              player.companions.contains(where: { $0.characterId == characterId }),
              !root.gameModel.gameRoster.players.contains(where: { $0.characterId == characterId }),
              !gameModel.isCharacterBound(characterId)
        else { return nil }
        return characterId
    }

    /// The companion handshake: a reference is answered only when this device lacks that
    /// version; a package is imported like a player's Character (the companion is its primary
    /// item) and then gets its pin. Live value updates are not taken for companions.
    private func handleCompanionStore(_ model: GameNetworkModel, characterId: UUID) async throws -> NetworkCodableDataType? {
        guard model.data.data != nil else {
            return await isCharacterOutOfDate(model, characterId: characterId) ? model.data : nil
        }
        guard await importPeerCharacter(model, characterId: characterId) else { return nil }
        // The pin waited for the Character to exist here.
        await resetPlayers()
        return nil
    }

    /// Whether the sender's Character reference names another version than this device holds.
    /// Exact versions mean the master already owns the package.
    private func isCharacterOutOfDate(_ model: GameNetworkModel, characterId: UUID) async -> Bool {
        let localVersion = await root.characterRoot.gameControllable.networkVersion(for: characterId)
        return localVersion != model.data.version
    }

    /// Imports a Character package from a player (its own Character or a companion): the sender
    /// may write that Character and the items it introduces, never another item this device
    /// already owns (CODE_AUDIT_15 §5.2; the policy's known gaps are accepted, see
    /// `PeerImportPolicy`, CODE_AUDIT_Folder §6.2, won't fix). On failure the player is told
    /// (`.failed`) so it can clear its "sent" flag and retry instead of waiting for a pin that
    /// never comes (CODE_AUDIT_Network §5.24, CODE_AUDIT_24 §5.5): player Characters and
    /// companions alike. Returns whether the import succeeded.
    private func importPeerCharacter(_ model: GameNetworkModel, characterId: UUID) async -> Bool {
        do {
            let policy = root.gameModel.peerImportPolicy(senderId: model.sender.id, primaryItemId: characterId)
            try await root.characterRoot.valueGameControllable.updatePlayer(data: model.data, policy: policy)
            root.gameModel.recordPeerImport(policy, senderId: model.sender.id)
            return true
        } catch {
            Logger.networking.error("MasterController: Failed to import Character package \(characterId, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            await send(
                type: .update,
                subtype: .failed,
                updated: NetworkCodableDataType(id: characterId, type: .value, version: model.data.version, data: nil),
                playerId: model.sender.id
            )
            return false
        }
    }

    /// Decodes, version-checks, and applies a `.valueUpdate` payload from a
    /// sender already known to be ownership-authorized for `characterId` —
    /// shared by the immediate receive path and the deferred-replay path
    /// triggered once a race with the join handshake resolves. See
    /// CODE_AUDIT_Network §5.18.
    private func applyValueUpdate(_ model: GameNetworkModel, characterId: UUID) {
        guard let update = GameValueEntryUpdate.decodeData(of: model.data.data),
              update.characterId == characterId,
              root.gameModel.canApplyValueUpdate(
                  senderId: model.sender.id,
                  characterId: characterId,
                  entryId: update.entryId,
                  timestamp: model.timestamp,
                  counter: model.counter
              ),
              root.characterRoot.valueGameControllable
                .applyGameValueEntryUpdate(update)
        else { return }
        root.gameModel.recordValueUpdate(
            senderId: model.sender.id,
            characterId: characterId,
            entryId: update.entryId,
            counter: model.counter
        )
    }

    /// Character synchronization can finish after resetPlayers() created and
    /// broadcast a pin without its Character photo. Re-publish both the
    /// structural pin metadata and authoritative live state once the Character
    /// is known so every peer replaces that bootstrap copy immediately.
    private func publishCurrentMapAfterPlayerPinChange() async {
        guard let mapId = root.mapRoot.mapGameControllable.gameModel.currentItemId,
              mayShareMapState(for: mapId) else {
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
