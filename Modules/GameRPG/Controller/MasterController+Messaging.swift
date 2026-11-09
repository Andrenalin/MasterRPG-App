// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// MARK: - Send Messages

extension MasterController {
    /// The transport this controller sends through: the game's own, or the private one a
    /// player's device hosts for its mirrors.
    var store: GameNetworkController {
        asProxy ? root.networkProxyStore : root.networkStore
    }

    func send(updated: NetworkCodableDataType) async {
        guard updated.type != .value else { return }
        await send(type: .store, subtype: .store, updated: updated)
    }

    /// Builds a master message, logs it and records it for the statistics. A message with a
    /// counter of its own is new; one that takes `counter` delivers what an earlier message
    /// named and belongs to that message's log row.
    func outgoingMessage(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        updated: NetworkCodableDataType,
        counter existingCounter: Int? = nil,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        playerId: UUID? = nil,
        authoritativeMaster: Bool? = nil
    ) -> GameNetworkModel {
        let counter = existingCounter ?? gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Built from local state in one MainActor hop; a playerId becomes the
        // message target so only the addressee processes it.
        let message = root.gameModel.outgoingMessage(
            timestamp: timestamp,
            counter: counter,
            type: type,
            subType: subtype,
            asMaster: authoritativeMaster ?? !asProxy,
            targetId: playerId,
            data: updated
        )
        if existingCounter == nil {
            gameModel.recordSentDelivery(counter: counter, type: type, module: updated.type, itemId: updated.id)
            root.logGameController.addMessage(
                messageID: GameDeliveryMessageID(sessionID: gameModel.deliverySessionId, counter: counter),
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id,
                targetID: playerId
            )
        }
        return message
    }

    /// Sends a master message. Without an origin or a player it goes to everyone; with an
    /// origin it answers the peer a request came from; with only a player it goes to that
    /// player, wherever it is connected.
    func send(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        updated: NetworkCodableDataType,
        counter: Int? = nil,
        timestamp: TimeInterval? = nil,
        appliesLocalSpaceTransform: Bool = true,
        connectionId: ConnectionController.ID? = nil,
        origin: GameMessageOrigin? = nil,
        playerId: UUID? = nil,
        authoritativeMaster: Bool? = nil
    ) async {
        // Tables are immutable during a game. Their complete state is exchanged
        // only through reveal/store requests; accepting an update would bypass
        // the versioned canonical-package handshake.
        guard type != .update || updated.type != .table else { return }

        let isBroadcast = origin == nil && connectionId == nil && playerId == nil
        if isBroadcast, !asProxy, type == .update, updated.type == .map {
            if subtype == .mapState {
                await sendMapContentIfChanged(before: updated)
            } else if subtype == .generic, let contentVersion = updated.contentVersion {
                gameModel.sentMapContentVersions[updated.id] = contentVersion
            }
        }

        let outgoingTimestamp: TimeInterval
        if let timestamp {
            outgoingTimestamp = timestamp
        } else if appliesLocalSpaceTransform {
            guard let stamped = root.outgoingTimestamp(type: type, subtype: subtype, updated: updated) else { return }
            outgoingTimestamp = stamped
        } else {
            outgoingTimestamp = Date.now.timeIntervalSince1970
        }

        let message = outgoingMessage(
            type: type,
            subtype: subtype,
            updated: updated,
            counter: counter,
            timestamp: outgoingTimestamp,
            playerId: playerId,
            authoritativeMaster: authoritativeMaster
        )

        if !asProxy, appliesLocalSpaceTransform, message.sender.isMaster {
            guard root.applyOwnSpaceTransform(message) else { return }
        }

        let deliveryOrigin = origin ?? connectionId.map { asProxy ? .proxy($0) : .direct($0) }
        await root.statisticsModel.record(
            message,
            direction: .outgoing,
            origin: deliveryOrigin ?? (asProxy ? .proxy(nil) : .direct(nil))
        )

        if let deliveryOrigin {
            await store.sendAsset(message, to: deliveryOrigin)
        } else if let playerId, !asProxy {
            await store.sendPlayer(message, toPlayer: playerId)
        } else {
            await store.sendPlayer(data: message)
        }
    }
}
