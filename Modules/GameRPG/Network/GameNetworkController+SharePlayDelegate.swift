// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities

// MARK: - SharePlayControllerDelegate

extension GameNetworkController: SharePlayControllerDelegate {
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async {
        // The messenger already yields messages in order. Await routing so that
        // order is not lost by creating one unstructured task per message.
        await routeSharePlayUpdate(model, id: id)
    }

    func handleFileUpdate(_ model: GameNetworkModel) async {
        // Journal snapshots are processed in message order. Await routing so that
        // order is preserved; independent unstructured tasks provide no FIFO guarantee.
        await routeSharePlayFileUpdate(model)
    }

    func handleFileLoadFailure(_ message: GameNetworkModel) async {
        // Only the game master's files matter to a player. Messenger does not echo a device's
        // own sends, so on the game-master device a master envelope is never its own.
        guard message.sender.isMaster, !model.hasLocalPlayer else { return }
        await model.playerDelegate?.sharePlayFileLoadFailed(message)
    }

    func sharePlayLostPlayer(id: UUID) async {
        sharePlayStore.unbindPlayer(participantId: id)
        await model.masterDelegate?.lostPlayer(for: id)
        await model.playerDelegate?.sharePlayParticipantLeft(id: id)
    }

    func sharePlayLostConnection() async {
        await model.playerDelegate?.lostConnection()
    }

    func sharePlaySessionConfigured() async {
        guard !model.hasLocalPlayer else { return }
        // Keep ready() in the GroupSession state loop. If list reporting
        // suspends, invalidation cannot overtake it and then be clobbered by
        // the obsolete ready operation resuming afterward.
        await model.playerDelegate?.ready()
    }

    func pinnedMasterParticipantId(among participantIds: [UUID]) async -> UUID? {
        guard let playerDelegate = model.playerDelegate else { return nil }
        for id in participantIds where await playerDelegate.isSharePlayMasterParticipant(id: id) {
            return id
        }
        return nil
    }

    func sharePlayJoinedPlayer(id: UUID) async {
        // `id` is a GroupActivities transport participant, not the player's
        // later in-game sender ID. Preserve that origin so replay is physically
        // addressed through Messenger and can never fall through to Bonjour.
        await model.masterDelegate?.ready(for: .sharePlay(id))
    }

    func routeSharePlayUpdate(_ message: GameNetworkModel, id: UUID) async {
        let origin = GameMessageOrigin.sharePlay(id)
        if message.sender.isMaster {
            // GroupSessionMessenger does not echo this device's own sends. On the
            // game-master device, the master's messages reach the co-located
            // PlayerController through sendPlayer instead, so an inbound envelope
            // claiming to be the master is another peer's.
            guard !model.hasLocalPlayer else {
                Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master message on the game-master device")
                return
            }
            await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            return
        }

        // Observers and proxies only exist on the local network.
        guard message.sender.role == .player else {
            Logger.networking.debug("GameNetworkController: Rejected local-only role on SharePlay from \(id)")
            return
        }

        if let masterDelegate = model.masterDelegate {
            guard await masterDelegate.accepts(message, origin: origin) else {
                Logger.networking.debug("GameNetworkController: Rejected SharePlay message from \(id)")
                return
            }
            sharePlayStore.bindPlayer(
                named: message.senderName,
                hasTable: message.senderPlatform == .visionOS,
                participantId: id
            )
            if message.isPlayerGroupEvent {
                // The session already delivered the event to the SharePlay players; the
                // local-network players get it from the game master.
                await model.masterStore?.sendResponse(data: message)
            }
            await masterDelegate.received(message, origin: origin)
            return
        }

        guard let playerDelegate = model.playerDelegate else { return }
        // The game master relays its local-network players into SharePlay; those players are
        // not session participants and have no seat at the 3D table.
        if await !playerDelegate.isSharePlayMasterParticipant(id: id) {
            sharePlayStore.bindPlayer(
                named: message.senderName,
                hasTable: message.senderPlatform == .visionOS,
                participantId: id
            )
        }
        // Everything else a player sends is for the game master only.
        guard message.isPlayerGroupEvent else { return }
        await playerDelegate.receivedSharePlay(message, participantId: id)
    }

    func routeSharePlayFileUpdate(_ message: GameNetworkModel) async {
        if message.sender.isMaster {
            // Journal snapshots include this device's own attachments, and the game master
            // already delivered those to its local player at send time.
            guard !model.hasLocalPlayer else {
                Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master file message on the game-master device")
                return
            }
            await model.playerDelegate?.receivedSharePlayFile(message)
            return
        }

        // A file a player uploads is a contribution to the game master, which shows it to the
        // group itself.
        guard message.sender.role == .player,
              let masterDelegate = model.masterDelegate,
              await masterDelegate.accepts(message, origin: .file)
        else { return }
        await masterDelegate.receivedFile(message)
    }
}
