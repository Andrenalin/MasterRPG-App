// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AudioRPG
import SpaceRPG

// MARK: - Send Messages

extension PlayerController {
    func send(updated: NetworkCodableDataType) async {
        guard root.gameModel.gameType != .observer else { return }
        guard updated.type != .value else { return }
        await send(type: .store, subType: .store, updated: updated)
    }

    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        if root.gameModel.gameType == .observer {
            // An observer only moves the player pins the game master gave it; the master
            // checks that before applying the move.
            guard message.type == .map, actionType == .mapPin else { return }
            await send(type: .update, subType: .mapPin, updated: message)
            return
        }
        // Players cannot publish Weather and Weather has no live updates yet.
        guard message.type != .table, message.type != .weather else { return }
        if message.type == .value {
            let playerCharacterId = root.gameModel.gamePlayer.characterId
            guard actionType == .valueUpdate,
                  message.data != nil,
                  message.id == playerCharacterId else {
                return
            }
            await send(type: .update, subType: .valueUpdate, updated: message)
            return
        }
        if actionType == .generic {
            switch message.type {
            case .photo, .pdf, .space:
                guard let access = FileBackedModuleAccess.access(for: message.type, in: root),
                      access.isSharingEnabled(root.gameModel.gameControl.features)
                else { return }
                let masterHasIt = access.masterVersion(message.id, root.gameModel.gameConfig.master.id) != nil
                await shareFile(message, masterHasIt: masterHasIt, controllable: access.controllable)
                return
            case .audio:
                guard root.gameModel.gameControl.features.audioSharing else { return }
                let masterHasIt = root.audioRoot.audioGameControllable.isAudioAvailable(
                    itemId: message.id,
                    for: root.gameModel.gameConfig.master.id
                )
                await shareFile(message, masterHasIt: masterHasIt, controllable: root.audioRoot.gameControllable)
                return
            default:
                break
            }
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.gameModel.gameControl.features.spaceSharing else { return }
        }
        if message.type == .audio {
            guard root.gameModel.gameControl.features.audioSharing else { return }
        }
        if message.type == .dice {
            guard root.gameModel.gameControl.features.dicePlayers else { return }
        }
        await send(type: .update, subType: actionType, updated: message)
    }

    /// Shows a file-backed item of this player to the group. The game master's copy is the one
    /// everybody sees: the player names the item and the master shows it, delivering it to
    /// whoever lacks it. The bytes go along only for an item the master has never reported,
    /// which it then adopts as its own copy.
    ///
    /// A bare reference is exported only when the master needs the bytes, so a file the master
    /// holds is never read into memory. A failed export is logged and nothing is sent: the
    /// master would only be told about an item it cannot get. See CODE_AUDIT_Audio2 §7.6.
    private func shareFile(
        _ data: NetworkCodableDataType,
        masterHasIt: Bool,
        controllable: any GameControllable
    ) async {
        guard !masterHasIt else {
            await send(type: .update, subType: .generic, updated: data.reference)
            return
        }
        var payload = data
        if payload.data == nil {
            guard await controllable.hasLocalFileData(for: data.id) else {
                Logger.networking.error("PlayerController: Cannot share \(data.type.token, privacy: .public) \(data.id, privacy: .public): its file is not on this device")
                return
            }
            do {
                payload = try await controllable.createGameData(for: data.id)
            } catch {
                Logger.networking.error("PlayerController: Failed to export \(data.type.token, privacy: .public) \(data.id, privacy: .public) for sharing: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return
            }
        }
        await send(type: .update, subType: .generic, updated: payload)
    }

    /// Sends a message of this player. Everything goes to the game master; a Dice roll, a
    /// moved pin and a Space transform also reach the other players and this device's
    /// mirrors. Passing `counter` echoes a master message; without it the message gets this
    /// player's next own counter.
    func send(
        counter: Int? = nil,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        updated: NetworkCodableDataType,
        relayToProxyClients: Bool = true
    ) async {
        // Tables have no live-update protocol. Only reveal/store messages may
        // carry their versioned canonical package.
        guard type != .update || updated.type != .table else { return }

        guard let outgoingTimestamp = root.outgoingTimestamp(type: type, subtype: subType, updated: updated) else { return }

        let outgoingCounter = counter ?? gameModel.nextOutgoingMessageCounter()
        Logger.networking.debug("PlayerController: Send \(outgoingCounter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networkData = root.gameModel.outgoingMessage(
            timestamp: outgoingTimestamp,
            counter: outgoingCounter,
            type: type,
            subType: subType,
            asMaster: false,
            data: updated
        )

        // A rejected own transform is still sent: the master decides about it.
        _ = root.applyOwnSpaceTransform(networkData)

        let origin: GameMessageOrigin = root.gameModel.gameType == .proxy ? .proxy(nil) : .direct(nil)
        await root.statisticsModel.record(networkData, direction: .outgoing, origin: origin)

        await sendUpstream(model: networkData)
        if relayToProxyClients,
           root.gameModel.gameType != .proxy,
           networkData.isPlayerGroupEvent {
            await root.networkProxyStore.sendPlayer(data: networkData)
        }
    }

    /// Remaps a private mirror's small group event to the host identity once,
    /// then sends that same envelope upstream and to sibling mirrors. The host
    /// controller has already applied the event locally.
    func relayProxyGroupEvent(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        guard source.groupEventKind != nil else { return }

        let outgoingCounter = gameModel.nextOutgoingMessageCounter()
        let remapped = root.gameModel.outgoingMessage(
            timestamp: source.timestamp,
            counter: outgoingCounter,
            type: source.type,
            subType: source.subType,
            asMaster: false,
            data: source.data
        )
        await root.statisticsModel.record(
            remapped,
            direction: .outgoing,
            origin: .proxy(connectionId)
        )
        await root.networkStore.sendMaster(data: remapped)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    static func shouldStartAudioPlayback(isSharePlayActive: Bool, asGameMaster: Bool) -> Bool {
        !isSharePlayActive || asGameMaster
    }

    /// Sends to the game master: through the host for a mirror, directly otherwise. Which
    /// transport carries it is the network controller's decision.
    func sendUpstream(model: GameNetworkModel) async {
        if root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model)
        }
    }
}
