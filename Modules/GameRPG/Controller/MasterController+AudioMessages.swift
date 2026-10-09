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
            let audio = root.audioRoot.audioGameControllable
            let wasMissingPlayers = !audio.missingPlayers(for: model.data.id).isEmpty
            let hasPendingPlay = gameModel.pendingAudioPlays[model.data.id] != nil
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await continuePendingAudioPlays()
            // Only the master collects the receipts. The one that completes a share is
            // announced, so a player's share button turns to play as well; a pending play
            // announces it with its play command instead.
            if wasMissingPlayers, !hasPendingPlay, audio.missingPlayers(for: model.data.id).isEmpty {
                await broadcastAudioList()
            }
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
                    let canonical = try await canonicalAudioReveal(for: model.data.id)
                    await send(type: .reveal, subtype: .show, updated: canonical)
                } catch ItemGameStorableError.itemMissing {
                    guard model.data.data != nil else { return nil }
                    // No import policy for the player's package: accepted, see `updateGame(data:hide:deep:)`
                    // (CODE_AUDIT_Folder §6.1, won't fix).
                    do {
                        try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                    } catch {
                        // A throw inside this `catch` body is not caught by the sibling `catch`
                        // below, so a failed import left the contributing player without an
                        // answer. See CODE_AUDIT_21 §5.10.
                        await reportFailedAudioContribution(model, error: error)
                        return nil
                    }
                    await send(type: .reveal, subtype: .show, updated: model.data)
                } catch {
                    // Previously this only logged, leaving the contributing
                    // player waiting indefinitely whenever the master's
                    // local copy isn't actually materialized yet (e.g. an
                    // undownloaded iCloud placeholder) rather than genuinely
                    // missing. Targeted at the sender only — unlike the
                    // broadcast `.show` sends in the success paths above,
                    // this failure is specific to this one contribution.
                    // See CODE_AUDIT_Network §5.12.
                    await reportFailedAudioContribution(model, error: error)
                }
            case .playAudio:
                guard root.gameModel.gameControl.features.audioSharing else { return nil }
                await requestAudioPlay(model.data)
            case .audioList:
                guard applyAudioList(model) else { return nil }
                resetAudioTransfers(for: model.sender.id)
                await broadcastAudioList()
                await continuePendingAudioPlays()
            default:
                break
            }
            return nil
        }
    }

    /// The master's own copy of an audio a player shared: the file for as long as a player
    /// misses it, the reference alone once everyone has it.
    private func canonicalAudioReveal(for itemId: UUID) async throws -> NetworkCodableDataType {
        let controllable = root.audioRoot.gameControllable
        guard await controllable.itemControllable.item(for: itemId) != nil else {
            throw ItemGameStorableError.itemMissing
        }
        guard root.audioRoot.audioGameControllable.missingPlayers(for: itemId).isEmpty else {
            return try await controllable.createGameData(for: itemId)
        }
        return await controllable.share(id: itemId)
    }

    /// Sends every player the authoritative report list: who has which audio.
    private func broadcastAudioList() async {
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id)
        await send(type: .update, subtype: .audioList, updated: audioList)
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
            gameModel.audioPlayRetryAttempts[id] = nil
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
            Logger.networking.error("MasterController: Cannot prepare pending audio \(id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            scheduleAudioPlayRetry(id: id)
        }
    }

    private static let audioPlayRetryDelay: Duration = .seconds(5)
    /// Caps the bounded retry so a permanently failing export (missing or
    /// corrupt file) stops re-exporting after this many attempts instead of
    /// retrying every `audioPlayRetryDelay` for the rest of the session.
    /// See CODE_AUDIT_17 §3.6.
    private static let maxAudioPlayRetryAttempts = 5

    /// Schedules one bounded retry of `fulfillPendingAudioPlay(id:data:)`
    /// after `audioPlayRetryDelay`, replacing any retry already scheduled
    /// for this item — so a persistently failing export doesn't pile up
    /// concurrent attempts. See CODE_AUDIT_Network §5.13.
    private func scheduleAudioPlayRetry(id: UUID) {
        let attempts = (gameModel.audioPlayRetryAttempts[id] ?? 0) + 1
        gameModel.audioPlayRetryAttempts[id] = attempts
        guard attempts <= Self.maxAudioPlayRetryAttempts else {
            Logger.networking.error("MasterController: Dropping pending audio \(id, privacy: .public) after \(attempts, privacy: .public) failed attempts.")
            audioPlayRetryTasks[id]?.cancel()
            audioPlayRetryTasks[id] = nil
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioTransferPlayers[id] = nil
            gameModel.audioPlayRetryAttempts[id] = nil
            return
        }

        audioPlayRetryTasks[id]?.cancel()
        audioPlayRetryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.audioPlayRetryDelay)
            guard !Task.isCancelled, let self else { return }
            self.audioPlayRetryTasks[id] = nil
            guard let data = self.gameModel.pendingAudioPlays[id] else { return }
            await self.fulfillPendingAudioPlay(id: id, data: data)
        }
    }

    /// Tells the contributing player that its audio item was not accepted. Targeted at the
    /// sender only — unlike the broadcast `.show` sends of the success paths — because the
    /// failure is specific to this one contribution. See CODE_AUDIT_Network §5.12.
    private func reportFailedAudioContribution(_ model: GameNetworkModel, error: any Error) async {
        Logger.networking.error("MasterController: Failed to import shared audio \(model.data.id, privacy: .public) as canonical copy: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        await send(
            type: .reveal,
            subtype: .failed,
            updated: NetworkCodableDataType(id: model.data.id, type: .audio, version: model.data.version, data: nil),
            replyToMessageID: model.messageID,
            playerId: model.sender.id
        )
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
                Logger.networking.error("MasterController: Failed to start audio playback for \(data.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
