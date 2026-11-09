// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import SpaceRPG
import PhotoRPG
import WeatherRPG

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
        // Reports are meaningless upstream — the master does not know the proxy exists. The host
        // is authoritative for the character and the audio availability, so the proxy's own
        // announcements drop too.
        if model.isAcknowledgement || model.isReportList {
            return true
        }
        if model.data.type == .value, model.type == .update, model.subType == .store {
            return true
        }

        // A Dice message of the proxy that is not a complete roll is dropped, like any other
        // Dice update.
        if model.data.type == .dice, model.type == .update, model.groupEventKind != .diceRoll {
            return true
        }
        if let kind = model.groupEventKind {
            guard await applyProxyGroupEvent(model, kind: kind) else { return true }
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.isAssetRequest {
            if await canServeProxyRequest(for: model.data) {
                do {
                    // Serve from the host's own game memory — local network is
                    // fast and the master never learns about the proxy.
                    // `authoritativeMaster` mirrors replayCurrentPresentation:
                    // the proxy's handlers only accept reveals from the master.
                    if let requestedData = try await proxyAnswerData(
                        for: model,
                        connectionId: connectionId
                    ) {
                        await send(
                            type: model.type,
                            subtype: model.subType,
                            updated: requestedData,
                            counter: model.counter > 0 ? model.counter : nil,
                            connectionId: connectionId,
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

    /// Applies a proxy client's group event to the host's own game, as the host player.
    /// Returns whether it was accepted and is relayed on.
    private func applyProxyGroupEvent(
        _ model: GameNetworkModel,
        kind: GameNetworkModel.GroupEventKind
    ) async -> Bool {
        switch kind {
        case .diceRoll:
            guard root.gameModel.gameControl.features.dicePlayers else { return false }
            // The proxy rolls as the host player — show it on the host as well.
            let hostName = root.gameModel.gamePlayer.name
            let hostSupporterTier = root.gameModel.gamePlayer.supporterTier
            _ = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: hostName,
                supporterTier: hostSupporterTier,
                isGameMaster: false
            )
            return true
        case .mapPin:
            // Update the host's own map first, then tell the master.
            return root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: model.data.id,
                data: model.data,
                playerId: root.gameModel.gameConfig.id
            )
        case .spaceTransform:
            guard root.gameModel.gameControl.features.spaceSharing,
                  root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data),
                  await root.spaceRoot.gameControllable.networkVersion(for: model.data.id) == model.data.effectiveAssetVersion
            else { return false }
            return root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: model.data,
                counter: model.counter,
                timestamp: model.timestamp
            )
        }
    }

    /// Asset requests bypass the normal peer-presentation handlers. Those
    /// handlers intentionally publish a player's reveal to the group, whereas
    /// a proxy answer must return the host's bytes only to the requesting
    /// private mirror.
    private func proxyAnswerData(
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
            return try await handle(model, origin: .direct(connectionId))
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
            counter: model.isAssetRequest ? model.counter : nil,
            type: model.type,
            subType: model.subType,
            updated: model.data,
            relayToProxyClients: false
        )
    }

    /// Whether the host holds everything needed to answer a proxy data request
    /// itself, including the binaries of file-backed modules.
    private func canServeProxyRequest(for data: NetworkCodableDataType) async -> Bool {
        switch data.type {
        case .photo, .pdf, .space:
            guard let access = FileBackedModuleAccess.access(for: data.type, in: root),
                  await access.controllable.hasLocalFileData(for: data.id)
            else { return false }
            return await access.controllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .audio:
            guard await root.audioRoot.audioGameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.audioRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
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
            // Always forward proxy requests for it to the real master.
            return false
        default:
            return true
        }
    }
}
