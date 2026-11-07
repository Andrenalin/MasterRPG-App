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

// MARK: - Send Messages

extension MasterController {
    /// The transport this controller sends through: the game's own, or the private one a
    /// player's device hosts for its mirrors.
    var store: GameNetworkController {
        asProxy ? root.networkProxyStore : root.networkStore
    }

    /// Shows an item to the players. Everyone gets its reference; the players that lack the
    /// item get its package (see `GameNetworkController.sendPresentation`). A player the
    /// reports did not show as lacking it answers with the same counter and is served by
    /// `process(_:)`.
    func show(for idType: NetworkCodableDataType) async {
        // Values are exchanged only as the joining player's Character. There
        // is no general Character/Value presentation protocol during a game.
        guard idType.type != .value else { return }

        if idType.type == .map {
            // Another map (or this one again) is shown: a pin photo shared earlier is over.
            root.mapRoot.mapGameControllable.clearSharedPinPhotos()
        }

        let reference: NetworkCodableDataType
        switch idType.type {
        case .map where idType.assetVersion == nil:
            // Call sites of older modules still construct the scale-only reference. The
            // background and content fingerprints are the versions players compare.
            reference = await root.mapRoot.mapGameControllable.shareMap(id: idType.id)
        case .weather:
            // Weather's package identity comes from its linked Photo.
            reference = await root.weatherRoot.weatherGameControllable.shareWeather(id: idType.id)
        default:
            reference = idType.reference
        }
        recordMasterVersion(of: reference)

        if let presentation = newMapPhotoPresentation(for: reference.type, itemId: reference.id) {
            // Before the reveal: a player shows the photo on the map as soon as it arrives.
            await broadcastMapPhoto(presentation)
        }
        if reference.type == .weather {
            // A shown weather also covers the 3D table, once a player holds it.
            await showTableWeather(reference.id)
        }

        let message = outgoingMessage(type: .reveal, subtype: .show, updated: reference)
        await root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPresentation(message, missingPlayers: playersMissing(reference)) { [self] in
            do {
                return try await createGameData(for: reference)
            } catch {
                Logger.networking.error("MasterController: Cannot create package for \(reference.type.token, privacy: .public) \(reference.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
        if reference.type == .map {
            await sendMapFollowUps(for: reference.id)
        }
        if reference.type == .audio {
            await showAudioStartItems(of: reference.id)
        }
    }

    /// The live part of a map after its reveal: the photo-free content, the state (rooms,
    /// pins, focus) and a running battle round. A paused "Share Map" keeps content and state
    /// private.
    func sendMapFollowUps(
        for mapId: UUID,
        origin: GameMessageOrigin? = nil,
        playerId: UUID? = nil
    ) async {
        let map = root.mapRoot.mapGameControllable
        if mayShareMapState(for: mapId) {
            await send(
                type: .update,
                subtype: .generic,
                updated: map.networkMapContentUpdate(for: mapId),
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
            await send(
                type: .update,
                subtype: .mapState,
                updated: map.networkMapUpdate(for: mapId),
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
        }
        if map.battleRoundModel.isRunning, let battleUpdate = map.networkBattleRoundUpdate(for: mapId) {
            await send(
                type: .update,
                subtype: .battleRound,
                updated: battleUpdate,
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
        }
    }

    /// A map state names the content version it belongs to. When the players last got another
    /// one, the content goes out first: a room the game master just revealed has text the
    /// players did not get while it was hidden.
    private func sendMapContentIfChanged(before state: NetworkCodableDataType) async {
        guard let contentVersion = state.contentVersion,
              gameModel.sentMapContentVersions[state.id] != contentVersion
        else { return }
        let content = await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: state.id)
        await send(type: .update, subtype: .generic, updated: content, authoritativeMaster: true)
    }

    /// The master's own version is the baseline every player's report is compared against.
    private func recordMasterVersion(of reference: NetworkCodableDataType) {
        let masterId = root.gameModel.gameConfig.id
        let version = reference.effectiveAssetVersion
        switch reference.type {
        case .photo:
            root.photoRoot.photoGameControllable.setMasterVersion(itemId: reference.id, version: version, masterId: masterId)
        case .pdf:
            root.pdfRoot.pdfGameControllable.setMasterVersion(itemId: reference.id, version: version, masterId: masterId)
        case .space:
            root.spaceRoot.spaceGameControllable.setMasterVersion(itemId: reference.id, version: version, masterId: masterId)
        default:
            break
        }
    }

    /// The players whose reports do not show the master's version of the item. Modules without
    /// reports (Map, Weather, Table) name nobody: their players ask.
    func playersMissing(_ reference: NetworkCodableDataType) -> Set<UUID> {
        let masterId = root.gameModel.gameConfig.id
        let players = root.gameModel.gameRoster.players.map(\.id).filter { $0 != masterId }
        switch reference.type {
        case .photo:
            let photo = root.photoRoot.photoGameControllable
            return Set(players.filter { !photo.isPhotoAvailable(itemId: reference.id, for: $0, masterId: masterId) })
        case .pdf:
            let pdf = root.pdfRoot.pdfGameControllable
            return Set(players.filter { !pdf.isPdfAvailable(itemId: reference.id, for: $0, masterId: masterId) })
        case .space:
            let space = root.spaceRoot.spaceGameControllable
            return Set(players.filter { !space.isSpaceAvailable(itemId: reference.id, for: $0, masterId: masterId) })
        case .audio:
            return Set(root.audioRoot.audioGameControllable.missingPlayers(for: reference.id))
        default:
            return []
        }
    }

    /// The package of an item, or `nil` when there is none to send: an export without the
    /// item's file (an iCloud file that has not downloaded) would only tell the players that
    /// they still lack it.
    ///
    /// The export requirements are `@concurrent`, so they run off the main actor by
    /// themselves and inherit this task's cancellation. See CODE_AUDIT_18 §7.1 and §4.4.
    func createGameData(for idType: NetworkCodableDataType) async throws -> NetworkCodableDataType? {
        switch idType.type {
        case .map:
            return try await root.mapRoot.mapGameControllable.createMapGameData(for: idType.id)
        case .photo:
            guard await root.photoRoot.gameControllable.hasLocalFileData(for: idType.id) else { return nil }
            return try await root.photoRoot.gameControllable.createGameData(for: idType.id)
        case .pdf:
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: idType.id) else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: idType.id)
        case .space:
            guard await root.spaceRoot.gameControllable.hasLocalFileData(for: idType.id) else { return nil }
            return try await root.spaceRoot.gameControllable.createGameData(for: idType.id)
        case .audio:
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: idType.id) else { return nil }
            return try await root.audioRoot.gameControllable.createGameData(for: idType.id)
        case .weather:
            return try await root.weatherRoot.weatherGameControllable.createWeatherGameData(for: idType.id)
        default:
            return nil
        }
    }

    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        // Weather is immutable during a game. It is presented and repaired via
        // reveal messages only; live update messages are not supported yet.
        guard message.type != .table, message.type != .weather else { return }
        // Character/Value updates have no general in-game protocol — the
        // player join handshake has its own exchange elsewhere, and the only
        // Value push a master can trigger here is `.addItem` (a Table-
        // generated outcome sent to a player as a new Character value).
        guard message.type != .value || actionType == .addItem else { return }
        if message.type == .dice,
           actionType == .generic,
           let diceResult = DiceResultModel.decodeData(of: message.data) {
            root.battleRoundController.recordDiceResult(
                diceResult,
                senderId: root.gameModel.gameConfig.id,
                isMaster: true
            )
        }
        if message.type == .audio, actionType == .playAudio {
            await requestAudioPlay(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.isValidSpaceTransform(message),
                  root.spaceRoot.gameControllable.gameModel.currentItemId == message.id
            else { return }
            let version = await root.spaceRoot.gameControllable.networkVersion(for: message.id)
            let canonical = NetworkCodableDataType(
                id: message.id,
                type: .space,
                version: version,
                data: message.data
            )
            await send(type: .update, subtype: .spaceTransform, updated: canonical, playerId: playerId)
            return
        }
        await send(type: .update, subtype: actionType, updated: message, playerId: playerId)
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
            root.logGameController.addMessage(
                messageID: GameDeliveryMessageID(sessionID: gameModel.deliverySessionID, counter: counter),
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
        } else if appliesLocalSpaceTransform,
                  type == .update,
                  subtype == .spaceTransform,
                  updated.type == .space {
            guard let causalTimestamp = root.spaceRoot.spaceGameControllable
                .causalSpaceTransformTimestamp(
                    itemId: updated.id,
                    version: updated.effectiveAssetVersion
                )
            else { return }
            outgoingTimestamp = causalTimestamp
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

        if !asProxy,
           appliesLocalSpaceTransform,
           message.sender.isMaster,
           type == .update,
           subtype == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: message.data,
                counter: message.counter,
                timestamp: message.timestamp
            ) else { return }
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
