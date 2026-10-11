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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Send Messages

extension PlayerController {
    func send(updated: NetworkCodableDataType) async {
        guard root.gameModel.gameType != .observer else { return }
        guard updated.type != .value else { return }
        await send(type: .store, subType: .store, updated: updated)
    }

    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        guard root.gameModel.gameType != .observer else { return }
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
            case .photo:
                guard root.gameModel.gameControl.features.photoSharing else { return }
                let masterId = root.gameModel.gameConfig.master.id
                let masterHasIt = root.photoRoot.photoGameControllable.masterVersion(for: message.id, masterId: masterId) != nil
                await shareFile(message, masterHasIt: masterHasIt)
                return
            case .pdf:
                let masterId = root.gameModel.gameConfig.master.id
                let masterHasIt = root.pdfRoot.pdfGameControllable.masterVersion(for: message.id, masterId: masterId) != nil
                await shareFile(message, masterHasIt: masterHasIt)
                return
            case .space:
                guard root.gameModel.gameControl.features.spaceSharing else { return }
                let masterId = root.gameModel.gameConfig.master.id
                let masterHasIt = root.spaceRoot.spaceGameControllable.masterVersion(for: message.id, masterId: masterId) != nil
                await shareFile(message, masterHasIt: masterHasIt)
                return
            case .audio:
                guard root.gameModel.gameControl.features.audioSharing else { return }
                let masterHasIt = root.audioRoot.audioGameControllable.isAudioAvailable(
                    itemId: message.id,
                    for: root.gameModel.gameConfig.master.id
                )
                await shareFile(message, masterHasIt: masterHasIt)
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
    private func shareFile(_ fullData: NetworkCodableDataType, masterHasIt: Bool) async {
        await send(
            type: .update,
            subType: .generic,
            updated: masterHasIt ? fullData.reference : fullData
        )
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

        let outgoingTimestamp: TimeInterval
        if type == .update,
           subType == .spaceTransform,
           updated.type == .space {
            guard let timestamp = root.spaceRoot.spaceGameControllable
                .causalSpaceTransformTimestamp(
                    itemId: updated.id,
                    version: updated.effectiveAssetVersion
                )
            else { return }
            outgoingTimestamp = timestamp
        } else {
            outgoingTimestamp = Date.now.timeIntervalSince1970
        }

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

        // Group transports do not echo a sender's own event, and the master does
        // not republish a Space transform. Apply this exact versioned envelope
        // optimistically so SpaceViewer observes its own timestamped transform
        // as acknowledged and does not retry forever.
        if networkData.type == .update,
           networkData.subType == .spaceTransform,
           networkData.data.type == .space {
            _ = root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networkData.data,
                counter: networkData.counter,
                timestamp: networkData.timestamp
            )
        }

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
        let isSupportedEvent = source.isDiceRollEvent ||
            (source.type == .update &&
             ((source.subType == .mapPin && source.data.type == .map) ||
              (source.subType == .spaceTransform && source.data.type == .space)))
        guard isSupportedEvent else { return }

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
