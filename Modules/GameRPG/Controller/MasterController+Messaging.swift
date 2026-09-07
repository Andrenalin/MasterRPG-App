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
    func show(for idType: NetworkCodableDataType) async {
        // Values are exchanged only as the joining player's Character. There
        // is no general Character/Value presentation protocol during a game.
        guard idType.type != .value else { return }

        // Map call sites from older modules/tests still construct the legacy
        // scale-only reference. Resolve the current background/content
        // fingerprints here so the Journal cache never falls back to that
        // mutable version.
        let resolvedIdType: NetworkCodableDataType
        if idType.type == .map, idType.assetVersion == nil {
            resolvedIdType = await root.mapRoot.mapGameControllable.shareMap(id: idType.id)
        } else if idType.type == .weather {
            // Weather's package identity comes from its linked Photo. Resolve it
            // here even for legacy/version-zero callers so the first-full cache
            // and Journal attachment use the canonical package version.
            resolvedIdType = await root.weatherRoot.weatherGameControllable.shareWeather(id: idType.id)
        } else {
            resolvedIdType = idType
        }
        if resolvedIdType.type == .space {
            let masterId = root.gameModel.gameConfig.id
            root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: resolvedIdType.id,
                version: resolvedIdType.effectiveAssetVersion,
                masterId: masterId
            )
        }
        // File-backed payloads are big (a map package carries background + pin +
        // player photos). The first show of each version ships the whole payload
        // right away — the id-then-request round trip would make every player wait
        // one extra full transfer, and over SharePlay the broadcast rides the
        // journal as one shared attachment. A same-version reshow sends only the
        // reference; players still holding the item show it from memory, the
        // others request it.
        if Self.sendsFullPayloadOnFirstShow(resolvedIdType.type), !gameModel.hasSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion) {
            // Reserved before the export `await` (not after it succeeds) so the
            // receive path can't independently decide to publish the same
            // item/version during the suspension and double the broadcast.
            // Rolled back below if the export fails. See CODE_AUDIT_Game §3.9.
            gameModel.markSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion)
            if let fullData = try? await createGameData(for: resolvedIdType) {
                await send(type: .reveal, subtype: .show, updated: fullData)
                if fullData.type == .map,
                   let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                       for: fullData.id
                   ),
                   root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
                    await send(type: .update, subtype: .battleRound, updated: battleUpdate)
                }
                return
            }
            gameModel.unmarkSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion)
            Logger.networking.error("MasterController: Cannot create package for \(resolvedIdType.type.token, privacy: .public) \(resolvedIdType.id, privacy: .public) — sending reference instead")
        }
        await send(type: .reveal, subtype: .show, updated: resolvedIdType)
        if resolvedIdType.type == .map,
           let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
               for: resolvedIdType.id
           ),
           root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
            await send(type: .update, subtype: .battleRound, updated: battleUpdate)
        }
    }

    static func sendsFullPayloadOnFirstShow(_ type: NetworkModules) -> Bool {
        switch type {
        case .map, .photo, .pdf, .space, .weather:
            true
        default:
            false
        }
    }

    /// `createGameData`/`createMapGameData`/`createWeatherGameData` are
    /// `nonisolated async` protocol requirements — under this project's
    /// approachable-concurrency setting they otherwise run on the *caller's*
    /// actor (see CODE_AUDIT_Game §3.1's mechanism), which for every call
    /// site of this dispatcher is the main actor. `Task.detached` here gives
    /// the export an explicit off-main starting point, matching the pattern
    /// `ImportControllable.importUrl` already uses; the implementation still
    /// hops back to the main actor itself for whatever pieces genuinely need
    /// it. Each controllable is fetched on the main actor first and handed
    /// into the detached task by value, rather than capturing `root` itself
    /// (a plain, non-`Sendable` class). See CODE_AUDIT_Game §3.5.
    private func createGameData(for idType: NetworkCodableDataType) async throws -> NetworkCodableDataType? {
        switch idType.type {
        case .map:
            let controllable = root.mapRoot.mapGameControllable
            return try await detachedGameData {
                try await controllable.createMapGameData(for: idType.id)
            }
        case .photo:
            let controllable = root.photoRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .pdf:
            let controllable = root.pdfRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .space:
            let controllable = root.spaceRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .weather:
            let controllable = root.weatherRoot.weatherGameControllable
            return try await detachedGameData {
                try await controllable.createWeatherGameData(for: idType.id)
            }
        default:
            return nil
        }
    }

    /// Runs `operation` on a detached, off-main task and propagates
    /// cancellation of the *caller's* task into it, matching the pattern
    /// used everywhere else in the codebase a detached task wraps an
    /// awaited result (e.g. `FoundrySystemPackageReader.read`,
    /// `FoundryVTTImportReader`, `ImportControllable.importUrl`). Without
    /// this, cancelling a reveal/repair/recovery left the detached export
    /// running to completion regardless. See CODE_AUDIT_9 §3.1.
    ///
    /// Not `private` because `MasterController+MapMessages.swift`'s
    /// `stableMapRecoveryBundle(for:)` also uses it, from a different file.
    func detachedGameData<Value: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: priority) {
            try await operation()
        }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
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

    func send(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        updated: NetworkCodableDataType,
        replyToMessageID: UUID? = nil,
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

        let counter = gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Built from local state in one MainActor hop; a playerId becomes the
        // message target so only the addressee processes it.
        let networtData = root.gameModel.outgoingMessage(
            replyToMessageID: replyToMessageID,
            timestamp: outgoingTimestamp,
            counter: counter,
            type: type,
            subType: subtype,
            asMaster: authoritativeMaster ?? !asProxy,
            targetId: playerId,
            data: updated
        )

        if !asProxy,
           appliesLocalSpaceTransform,
           networtData.sender.isMaster,
           type == .update,
           subtype == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networtData.data,
                counter: networtData.counter,
                timestamp: networtData.timestamp
            ) else { return }
        }

        if let wireID = networtData.messageID {
            let deliveryID = gameModel.trackDelivery(
                wireID: wireID,
                counter: counter
            )
            root.logGameController.addMessage(
                messageID: deliveryID,
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id,
                targetID: networtData.targetId
            )
        } else {
            root.logGameController.addMessage(
                counter: counter,
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id
            )
        }
        let deliveryOrigin = origin ?? (asProxy ? .proxy(connectionId) : .direct(connectionId))
        await root.statisticsModel.record(
            networtData,
            direction: .outgoing,
            origin: deliveryOrigin
        )

        if asProxy {
            if let targetConnectionId = origin?.connectionId ?? connectionId {
                await root.networkProxyStore.sendPlayer(networtData, to: targetConnectionId)
            } else {
                await root.networkProxyStore.sendPlayer(data: networtData)
            }
        } else if let origin {
            await root.networkStore.sendPlayer(networtData, to: origin)
        } else if let connectionId {
            await root.networkStore.sendPlayer(networtData, to: connectionId)
        } else {
            await root.networkStore.sendPlayer(data: networtData, fileJournal: Self.usesFileJournal(for: networtData))
        }
    }

    static func usesFileJournal(for model: GameNetworkModel) -> Bool {
        model.usesFileJournal
    }

    static func usesFileJournal(for data: NetworkCodableDataType) -> Bool {
        data.usesFileJournal
    }
}
