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

// MARK: - Audio Messages

extension MasterController {
    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await continuePendingAudioPlays()
            return nil
        }
        if model.subType == .failed {
            audioTransferFailed(itemId: model.data.id, playerId: model.sender.id)
            return nil
        }
        switch model.type {
        case .reveal, .store:
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .generic:
                guard root.gameModel.gameControl.features.audioSharing else { return nil }
                // Defend the master's own canonical copy first — mirrors
                // handlePhoto/handlePdf/handleSpace's `.itemMissing` import
                // fallback (this is also the legitimate path for a player
                // contributing a brand-new audio item the master has never
                // seen, exercised by PlayerMasterControllerTests.handleAudio).
                // The previous version of this fix unconditionally required
                // local data first, which blocked that legitimate case; the
                // actual vulnerability was importing an admitted player's
                // bytes over an *existing* master-owned copy with no check
                // at all — this restores that check. See CODE_AUDIT_Game §6.2.
                do {
                    let canonical = try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
                    await send(type: .reveal, subtype: .show, updated: canonical)
                } catch ItemGameStorableError.itemMissing {
                    guard model.data.data != nil else { return nil }
                    try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                    await send(type: .reveal, subtype: .show, updated: model.data)
                } catch {
                    Logger.networking.error("MasterController: Failed to import shared audio \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                }
            case .playAudio:
                guard root.gameModel.gameControl.features.audioSharing else { return nil }
                await requestAudioPlay(model.data)
            case .audioList:
                guard applyAudioList(model) else { return nil }
                resetAudioTransfers(for: model.sender.id)
                let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id)
                await send(type: .update, subtype: .audioList, updated: audioList)
                await continuePendingAudioPlays()
            default:
                break
            }
            return nil
        }
    }

    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyAudioList(from: model.sender.id, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.sender.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordAudioList(counter: model.counter, from: model.sender.id)
        return true
    }

    func requestAudioPlay(_ data: NetworkCodableDataType) async {
        if !root.audioRoot.audioGameControllable.shouldPlay(with: data) {
            gameModel.pendingAudioPlays[data.id] = nil
            gameModel.audioTransferPlayers[data.id] = nil
            await broadcastAudioPlay(data)
            return
        }

        gameModel.pendingAudioPlays[data.id] = data
        await fulfillPendingAudioPlay(id: data.id, data: data)
    }

    /// Not `private` because `MasterController+Control.swift`'s
    /// `performResetPlayers()` also calls this directly, from a different file.
    func continuePendingAudioPlays() async {
        let pending = gameModel.pendingAudioPlays
        for (id, data) in pending {
            await fulfillPendingAudioPlay(id: id, data: data)
        }
    }

    private func fulfillPendingAudioPlay(id: UUID, data: NetworkCodableDataType) async {
        let missingPlayers = Set(root.audioRoot.audioGameControllable.missingPlayers(for: id))
        if missingPlayers.isEmpty {
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioTransferPlayers[id] = nil
            await broadcastAudioPlay(data)
            return
        }

        let inFlight = gameModel.audioTransferPlayers[id] ?? []
        let newPlayers = missingPlayers.subtracting(inFlight)
        guard !newPlayers.isEmpty else { return }

        do {
            gameModel.audioTransferPlayers[id] = inFlight.union(newPlayers)
            let audioData = try await root.audioRoot.gameControllable.createGameData(for: id)
            guard gameModel.pendingAudioPlays[id] != nil else {
                gameModel.audioTransferPlayers[id] = nil
                return
            }
            let stillMissing = Set(root.audioRoot.audioGameControllable.missingPlayers(for: id))
                .intersection(newPlayers)
            if !stillMissing.isEmpty {
                // Audio repairs use GroupSessionJournal, whose attachment is
                // visible to the whole SharePlay session. Publishing the same
                // package once per missing logical player serializes duplicate
                // uploads and makes playback appear to hang. An untargeted
                // store is idempotent and also keeps Bonjour/local peers in
                // sync with a single transfer.
                await send(type: .store, subtype: .show, updated: audioData)
            }
        } catch {
            gameModel.audioTransferPlayers[id]?.subtract(newPlayers)
            Logger.networking.error("MasterController: Cannot prepare pending audio \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func audioTransferFailed(itemId: UUID, playerId: UUID) {
        gameModel.audioTransferPlayers[itemId]?.remove(playerId)
    }

    private func resetAudioTransfers(for playerId: UUID) {
        for itemId in gameModel.audioTransferPlayers.keys {
            gameModel.audioTransferPlayers[itemId]?.remove(playerId)
        }
    }

    private func broadcastAudioPlay(_ data: NetworkCodableDataType) async {
        await send(type: .update, subtype: .playAudio, updated: data)
        let hasLocalPlayer = root.networkStore.model.hasLocalPlayer
        if !hasLocalPlayer {
            // A failed playlist load/playback start used to be silently
            // swallowed here. See CODE_AUDIT_Game §4.2.
            do {
                try await root.audioRoot.audioGameControllable.play(with: data)
            } catch {
                Logger.networking.error("MasterController: Failed to start audio playback for \(data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
