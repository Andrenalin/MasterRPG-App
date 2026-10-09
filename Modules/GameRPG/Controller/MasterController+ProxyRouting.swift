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

// MARK: - Proxy host routing

extension MasterController {
    /// Routes a proxy client's message. The proxy device is a private mirror of
    /// the host player: nothing leaves this device with the proxy's identity,
    /// so the master and the other players never see it.
    ///
    /// Not `private` because `MasterController+NetworkStoreDelegate.swift`'s
    /// `process(_:)` also calls this directly, from a different file.
    func processAsProxy(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID?
    ) async -> Bool {
        // Reports and screens are meaningless upstream — the master does not
        // know the proxy exists. The host is authoritative for the character
        // and the audio availability, so the proxy's own announcements drop too.
        if model.isAcknowledgement || model.subType == .screen || model.subType == .audioList || model.subType == .photoList || model.subType == .pdfList || model.subType == .spaceList {
            return true
        }
        if model.data.type == .value, model.type == .update, model.subType == .store {
            return true
        }

        if model.data.type == .dice, model.type == .update {
            guard model.isDiceRollEvent else { return true }
            guard root.gameModel.gameControl.features.dicePlayers else { return true }
            // The proxy rolls as the host player — show it on the host as well.
            let hostName = root.gameModel.gamePlayer.name
            let hostSupporterTier = root.gameModel.gamePlayer.supporterTier
            _ = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: hostName,
                supporterTier: hostSupporterTier,
                isGameMaster: false
            )
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.data.type == .map,
           model.type == .update,
           model.subType == .mapPin,
           model.purpose == .event {
            // Update the host's own map first, then tell the master.
            let hostId = root.gameModel.gameConfig.id
            guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: model.data.id,
                data: model.data,
                playerId: hostId
            ) else {
                return true
            }
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.data.type == .space,
           model.type == .update,
           model.subType == .spaceTransform,
           model.purpose == .event {
            guard root.gameModel.gameControl.features.spaceSharing,
                  root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data),
                  await root.spaceRoot.gameControllable.networkVersion(for: model.data.id) == model.data.effectiveAssetVersion,
                  root.spaceRoot.spaceGameControllable.applySpaceTransform(
                      data: model.data,
                      counter: model.counter,
                      timestamp: model.timestamp
                  )
            else { return true }
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.purpose == .event,
           model.type == .reveal,
           model.subType == .show,
           (model.data.type == .photo || model.data.type == .pdf || model.data.type == .space) {
            guard let playerController = root.gameModel.playerController else {
                await remapUpstream(model)
                return true
            }
            // One host envelope drives all three destinations: upstream, the
            // co-located player, and sibling mirrors. Excluding the source
            // connection prevents an echo receipt from the initiating mirror.
            await playerController.relayProxyPresentation(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.purpose == .assetRequest {
            if await canServeProxyRequest(for: model.data) {
                do {
                    // Serve from the host's own game memory — local network is
                    // fast and the master never learns about the proxy.
                    // `authoritativeMaster` mirrors replayCurrentPresentation:
                    // the proxy's handlers only accept reveals from the master.
                    if let requestedData = try await proxyRepairData(
                        for: model,
                        connectionId: connectionId
                    ) {
                        await send(
                            type: model.type,
                            subtype: model.subType,
                            updated: requestedData,
                            connectionId: connectionId,
                            playerId: model.sender.id,
                            authoritativeMaster: true
                        )
                    }
                    return true
                } catch {
                    // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
                    Logger.networking.error("MasterController: Cannot serve proxy request locally \(model.debugDescription, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                }
            }
            // The host lacks the data itself — ask the master as the host. The
            // targeted answer is forwarded to the proxy with the target cleared.
            await remapUpstream(model)
            return true
        }

        await remapUpstream(model)
        return true
    }

    /// Asset requests bypass the normal peer-presentation handlers. Those
    /// handlers intentionally publish a player's reveal to the group, whereas
    /// a proxy repair must return the host's bytes only to the requesting
    /// private mirror.
    private func proxyRepairData(
        for model: GameNetworkModel,
        connectionId: ConnectionController.ID?
    ) async throws -> NetworkCodableDataType? {
        switch model.data.type {
        case .audio:
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        case .photo:
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        case .pdf:
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        case .space:
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        default:
            return try await handle(model, connectionId: connectionId)
        }
    }

    /// Re-sends a proxy client's message as the host player's own — fresh host
    /// counter, host sender identity, same payload.
    private func remapUpstream(_ model: GameNetworkModel) async {
        guard let playerController = root.gameModel.playerController else {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: No player controller to remap proxy message \(model.debugDescription, privacy: .private)")
            return
        }
        // This message came from a proxy client. Sending it upstream must not
        // broadcast the request back to that same proxy (or its siblings),
        // otherwise every mirror can request the same missing payload again.
        await playerController.send(
            type: model.type,
            subType: model.subType,
            updated: model.data,
            relayToProxyClients: false,
            purpose: model.purpose
        )
    }

    /// Whether the host holds everything needed to answer a proxy data request
    /// itself, including the binaries of file-backed modules.
    private func canServeProxyRequest(for data: NetworkCodableDataType) async -> Bool {
        switch data.type {
        case .photo:
            guard await root.photoRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.photoRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .pdf:
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.pdfRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .audio:
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: data.id) else { return false }
            return await root.audioRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .space:
            guard await root.spaceRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.spaceRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .map:
            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: data.id) else { return false }
            guard await root.mapRoot.mapGameControllable.missingMapImages(itemId: data.id).isEmpty else {
                return false
            }
            let localReference = await root.mapRoot.mapGameControllable.shareMap(id: data.id)
            if let requestedAssetVersion = data.assetVersion,
               requestedAssetVersion != localReference.assetVersion {
                return false
            }
            if let requestedContentVersion = data.contentVersion,
               requestedContentVersion != localReference.contentVersion {
                return false
            }
            return true
        case .weather:
            return root.weatherRoot.weatherGameControllable.isWeatherAvailable(
                itemId: data.id,
                version: data.version
            )
        case .table:
            // A player's current-session Table is a CRDT merge with its local
            // copy and may no longer equal the game master's canonical package.
            // Always forward proxy repairs to the real master.
            return false
        default:
            return true
        }
    }
}
