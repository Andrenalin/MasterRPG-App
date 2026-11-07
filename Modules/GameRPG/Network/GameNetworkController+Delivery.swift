// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// How a message reaches its recipients. The game controllers say what to send and to whom;
// which transport carries it, and whether file bytes travel at all, is decided here.

// MARK: - Master send

extension GameNetworkController {
    /// Sends a message to every player: all local-network connections, the SharePlay session
    /// and the player on this device.
    func sendPlayer(data: GameNetworkModel) async {
        await model.masterStore?.sendResponse(data: data)
        if !proxy {
            sharePlayStore.sendDataReportingLoss(data)
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        }
    }

    /// Presents an item to every player. `reference` names it; `package` builds its bytes and
    /// is called only when at least one of `missingPlayers` can be reached.
    ///
    /// A local-network player that lacks the item gets the package on its own connection,
    /// before the reference. For SharePlay players the package is uploaded to the Journal
    /// once, where everyone who lacks it loads it. A player the master did not know to lack the
    /// item asks for it with the counter of the reference; `sendAsset(_:to:)` answers.
    func sendPresentation(
        _ reference: GameNetworkModel,
        missingPlayers: Set<UUID>,
        package: () async -> NetworkCodableDataType?
    ) async {
        var connectionIds: [ConnectionController.ID] = []
        var sharePlayPlayerIsMissing = false
        for playerId in missingPlayers {
            switch model.playerRoutes.origin(for: playerId) {
            case let .direct(connectionId?), let .proxy(connectionId?):
                connectionIds.append(connectionId)
            case .sharePlay:
                sharePlayPlayerIsMissing = true
            case .direct(nil), .proxy(nil), .file, .local, nil:
                break
            }
        }

        if !connectionIds.isEmpty || sharePlayPlayerIsMissing, let payload = await package() {
            var full = reference
            full.data = payload
            if !connectionIds.isEmpty, let bytes = await encodedOffMain(full) {
                let encoded = PreEncodedMessage(bytes: bytes)
                for connectionId in connectionIds {
                    _ = await model.masterStore?.sendResponse(data: encoded, id: connectionId)
                }
            }
            if sharePlayPlayerIsMissing, !proxy {
                sharePlayStore.publishAsset(full, isPlaylist: isAudioPlaylist(full))
            }
        }
        await sendPlayer(data: reference)
    }

    /// Whether the package of `message` is an audio playlist, which the Journal holds in a slot
    /// of its own: the first track is shown right after it and would replace it.
    private func isAudioPlaylist(_ message: GameNetworkModel) -> Bool {
        message.data.type == .audio && model.isAudioPlaylist?(message.data.id) == true
    }

    /// Sends a message to the peer a request came from, over the transport that carried the
    /// request. A package goes to a local-network player on its own connection and to a
    /// SharePlay participant through the Journal, which skips a package it already holds for
    /// this show. A small message is addressed to the SharePlay participant itself; a
    /// participant id is not a connection id and never falls through to the other transport.
    func sendAsset(_ data: GameNetworkModel, to origin: GameMessageOrigin) async {
        switch origin {
        case let .direct(connectionId?), let .proxy(connectionId?):
            await sendPlayer(data, to: connectionId)
        case .direct(nil):
            await sendPlayer(data: data)
        case .proxy(nil):
            break
        case let .sharePlay(participantId):
            guard !proxy else { return }
            if data.carriesAsset {
                sharePlayStore.publishAsset(data, isPlaylist: isAudioPlaylist(data))
            } else {
                sharePlayStore.sendDataReportingLoss(data, participantId: participantId)
            }
        case .file:
            // A Journal callback does not name its participant; the Journal reaches everyone.
            guard !proxy else { return }
            sharePlayStore.publishAsset(data, isPlaylist: isAudioPlaylist(data))
        case .local:
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        }
    }

    /// Sends a message to one player, wherever that player is connected. A player this device
    /// has no route to gets it by broadcast; its target id keeps the others from applying it.
    func sendPlayer(_ data: GameNetworkModel, toPlayer playerId: UUID) async {
        if let origin = model.playerRoutes.origin(for: playerId) {
            await sendAsset(data, to: origin)
        } else {
            await sendPlayer(data: data)
        }
    }

    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        let delivered = await model.masterStore?.sendResponse(data: data, id: connectionId) ?? false
        guard delivered else {
            Logger.networking.debug("GameNetworkController: Target connection \(connectionId, privacy: .public) is no longer available")
            return
        }
    }

    /// Relays a host-remapped proxy event to every private mirror except the one that
    /// originated it. The originating mirror has already applied its own action.
    func sendPlayer(data: GameNetworkModel, except connectionId: ConnectionController.ID) async {
        guard proxy else { return }
        await model.masterStore?.sendResponse(data: data, except: connectionId)
    }
}

// MARK: - Player send

extension GameNetworkController {
    /// Sends a player's message to the game master. On SharePlay a file the player contributes
    /// travels through the Journal; everything else through Messenger.
    func sendMaster(data: GameNetworkModel) async {
        if !proxy { guard !model.hasLocalPlayer else { return } }
        await model.playerStore?.request(with: data)
        guard !proxy else { return }
        if data.carriesAsset {
            sharePlayStore.publishAsset(data, isPlaylist: isAudioPlaylist(data))
        } else {
            sharePlayStore.sendDataReportingLoss(data)
        }
    }
}
