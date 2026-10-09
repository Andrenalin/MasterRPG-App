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
            // Value updates are small causal events and deliberately stay on
            // Messenger/chunked transports, never GroupSessionJournal.
            await send(
                type: .update,
                subType: .valueUpdate,
                updated: message,
                useJournal: false
            )
            return
        }
        if message.type == .photo, actionType == .generic {
            guard root.gameModel.gameControl.features.photoSharing else { return }
            await sharePhoto(message)
            return
        }
        if message.type == .pdf, actionType == .generic {
            await sharePdf(message)
            return
        }
        if message.type == .space, actionType == .generic {
            await shareSpace(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.gameModel.gameControl.features.spaceSharing else { return }
        }
        if message.type == .audio {
            guard root.gameModel.gameControl.features.audioSharing else { return }
            if actionType == .generic {
                await shareAudio(message)
                return
            }
        }
        if message.type == .dice {
            guard root.gameModel.gameControl.features.dicePlayers else { return }
        }
        await send(type: .update, subType: actionType, updated: message)
    }

    /// The game master's copy is canonical: where it has the audio, the player only names it
    /// and the master delivers it to the players still missing it. The bytes go along only
    /// for audio the master has never seen, which it adopts as its own copy.
    private func shareAudio(_ fullData: NetworkCodableDataType) async {
        let masterHasAudio = root.audioRoot.audioGameControllable.isAudioAvailable(
            itemId: fullData.id,
            for: root.gameModel.gameConfig.master.id
        )
        let outgoing = masterHasAudio
            ? NetworkCodableDataType(id: fullData.id, type: fullData.type, version: fullData.version)
            : fullData
        await send(type: .update, subType: .generic, updated: outgoing)
    }

    /// Shared share skeleton for the three file-backed modules
    /// (Pdf, Photo, Space) — `sharePdf`/`sharePhoto`/`shareSpace` below
    /// previously hand-duplicated this exact control flow, differing only
    /// in which module's accessors they called and the `NetworkModules`
    /// case passed to `setGameUpdateType`. Every other module-specific
    /// concern (Space's `spaceSharing` feature gate) stays in that module's
    /// own thin wrapper. See CODE_AUDIT_10 §9.2.
    ///
    /// A player never uploads a file the game master already has: it names the
    /// item and the master delivers its own copy to whoever misses it.
    private func shareFileItem(
        _ fullData: NetworkCodableDataType,
        updateType: NetworkModules,
        masterVersion: (_ itemId: UUID, _ masterId: UUID) -> Int?,
        isAvailable: (_ itemId: UUID, _ playerId: UUID, _ masterId: UUID) -> Bool,
        allPlayersReported: (_ itemId: UUID) -> Bool,
        setCurrent: (_ itemId: UUID) async -> Bool
    ) async {
        // `PlayerController` is itself `@MainActor`, so this is already a
        // same-actor synchronous read — no actor hop needed.
        let (playerId, masterId) = (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        let baseline = masterVersion(fullData.id, masterId)
        let senderIsAvailable = isAvailable(fullData.id, playerId, masterId)
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        if senderIsAvailable, matchesBaseline {
            let reference = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: nil,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            let allPlayersHaveIt = allPlayersReported(fullData.id)
            if await setCurrent(fullData.id) {
                gameModel.setGameUpdateType(updateType)
            }
            if allPlayersHaveIt {
                // Everyone holds the master's version: the reference presents it to the group.
                await send(type: .reveal, subType: .show, updated: reference)
            } else {
                // Someone misses it. Only the master is asked, and it broadcasts its
                // canonical copy to the group (`MasterController`'s `.update/.generic`).
                await send(type: .update, subType: .generic, updated: reference)
            }
            return
        }

        let outgoing: NetworkCodableDataType
        if baseline == nil {
            // The master has no copy at all — unlike a mismatched/competing
            // edit of an item the master already owns, there is no canonical
            // baseline to defer to. Attach the full bytes so the master can
            // adopt them as its own copy (mirrors MasterController's
            // `.itemMissing` import fallback, which otherwise has nothing to
            // import and silently drops the reveal).
            outgoing = fullData
        } else {
            // The game master's file/version is canonical. A missing or stale
            // player report is a request for that asset, never an upload.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)
    }

    private func sharePhoto(_ fullData: NetworkCodableDataType) async {
        await shareFileItem(
            fullData,
            updateType: .photo,
            masterVersion: { root.photoRoot.photoGameControllable.masterVersion(for: $0, masterId: $1) },
            isAvailable: { root.photoRoot.photoGameControllable.isPhotoAvailable(itemId: $0, for: $1, masterId: $2) },
            allPlayersReported: { root.photoRoot.gameControllable.allPlayersReported(for: $0) },
            setCurrent: {
                guard await root.photoRoot.gameControllable.setCurrent(itemId: $0) else { return false }
                root.photoRoot.photoGameControllable.presentPhoto(itemId: $0)
                return true
            }
        )
    }

    private func sharePdf(_ fullData: NetworkCodableDataType) async {
        await shareFileItem(
            fullData,
            updateType: .pdf,
            masterVersion: { root.pdfRoot.pdfGameControllable.masterVersion(for: $0, masterId: $1) },
            isAvailable: { root.pdfRoot.pdfGameControllable.isPdfAvailable(itemId: $0, for: $1, masterId: $2) },
            allPlayersReported: { root.pdfRoot.gameControllable.allPlayersReported(for: $0) },
            setCurrent: { await root.pdfRoot.gameControllable.setCurrent(itemId: $0) }
        )
    }

    private func shareSpace(_ fullData: NetworkCodableDataType) async {
        guard root.gameModel.gameControl.features.spaceSharing else { return }
        await shareFileItem(
            fullData,
            updateType: .space,
            masterVersion: { root.spaceRoot.spaceGameControllable.masterVersion(for: $0, masterId: $1) },
            isAvailable: { root.spaceRoot.spaceGameControllable.isSpaceAvailable(itemId: $0, for: $1, masterId: $2) },
            allPlayersReported: { root.spaceRoot.gameControllable.allPlayersReported(for: $0) },
            setCurrent: { await root.spaceRoot.gameControllable.setCurrent(itemId: $0) }
        )
    }

    func send(
        counter: Int? = nil,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        updated: NetworkCodableDataType,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true,
        purpose: GameMessagePurpose = .event
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

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter: Int
        if let counter {
            outgoingCounter = counter
        } else {
            outgoingCounter = gameModel.nextOutgoingMessageCounter()
        }
        Logger.networking.debug("PlayerController: Send \(outgoingCounter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networkData = root.gameModel.outgoingMessage(
            timestamp: outgoingTimestamp,
            counter: outgoingCounter,
            type: type,
            subType: subType,
            asMaster: false,
            purpose: purpose,
            data: updated
        )

        // Group transports do not echo a sender's own event, and the master no
        // longer republishes a canonical Space transform. Apply this exact
        // versioned envelope optimistically so SpaceViewer observes its own
        // timestamped transform as acknowledged and does not retry forever.
        if networkData.purpose == .event,
           networkData.type == .update,
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

        let useOnTypeJournal = useJournal || Self.usesFileJournal(for: networkData)
        await sendOriginating(
            model: networkData,
            useJournal: useOnTypeJournal,
            relayToProxyClients: relayToProxyClients
        )
    }

    /// Turns one private mirror's presentation into one canonical host-player
    /// event. The same remapped envelope is used for the upstream send, sibling
    /// mirrors, and the co-located host player so transport retries cannot mint
    /// independent counters or identities for a single user gesture.
    func relayProxyPresentation(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        guard source.purpose == .event,
              source.type == .reveal,
              source.subType == .show,
              (source.data.type == .photo || source.data.type == .pdf || source.data.type == .space)
        else { return }

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter = gameModel.nextOutgoingMessageCounter()
        let remapped = root.gameModel.outgoingMessage(
            timestamp: source.timestamp,
            counter: outgoingCounter,
            type: source.type,
            subType: source.subType,
            asMaster: false,
            purpose: source.purpose,
            data: source.data
        )

        Logger.networking.debug("PlayerController: Relay proxy presentation \(outgoingCounter, privacy: .public) for \(source.data.type.token, privacy: .public) -> \(source.data.id, privacy: .public)")
        await root.statisticsModel.record(remapped, direction: .outgoing, origin: .proxy(connectionId))

        // Upstream exactly once. In particular, local application below must
        // never manufacture an acknowledgement or repair request of its own.
        await root.networkStore.sendMaster(
            data: remapped,
            fileJournal: Self.usesFileJournal(for: remapped)
        )

        // A private mirror cannot establish a new asset generation. Apply the
        // optimistic local presentation only when it matches the authoritative
        // master baseline; otherwise the master's canonical response will drive
        // the host and mirrors in the regular path.
        guard await canApplyRemappedProxyPresentation(remapped) else { return }
        await receivedProcess(remapped, origin: .local)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
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
            (source.purpose == .event &&
             source.type == .update &&
             ((source.subType == .mapPin && source.data.type == .map) ||
              (source.subType == .spaceTransform && source.data.type == .space)))
        guard isSupportedEvent else { return }

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter = gameModel.nextOutgoingMessageCounter()
        let remapped = root.gameModel.outgoingMessage(
            timestamp: source.timestamp,
            counter: outgoingCounter,
            type: source.type,
            subType: source.subType,
            asMaster: false,
            purpose: source.purpose,
            data: source.data
        )
        await root.statisticsModel.record(
            remapped,
            direction: .outgoing,
            origin: .proxy(connectionId)
        )
        await root.networkStore.sendMaster(data: remapped, fileJournal: false)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    private func canApplyRemappedProxyPresentation(_ model: GameNetworkModel) async -> Bool {
        let masterId = root.gameModel.gameConfig.master.id
        let version = model.data.effectiveAssetVersion

        switch model.data.type {
        case .photo:
            guard root.gameModel.gameControl.features.photoSharing else { return false }
            return root.photoRoot.photoGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .pdf:
            return root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .space:
            guard root.gameModel.gameControl.features.spaceSharing else { return false }
            return root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        default:
            return false
        }
    }

    static func usesFileJournal(for model: GameNetworkModel) -> Bool {
        model.usesFileJournal || usesFileJournal(type: model.type, subType: model.subType, data: model.data)
    }

    static func usesFileJournal(for data: NetworkCodableDataType) -> Bool {
        data.usesFileJournal
    }

    static func usesFileJournal(type: RPGMessageType, subType: RPGMessageActionType, data: NetworkCodableDataType) -> Bool {
        type == .update && subType == .generic && data.type == .audio && data.data != nil
    }

    static func shouldStartAudioPlayback(isSharePlayActive: Bool, asGameMaster: Bool) -> Bool {
        !isSharePlayActive || asGameMaster
    }

    private func sendOriginating(
        model: GameNetworkModel,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true
    ) async {
        if root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: useJournal)
            if relayToProxyClients, model.effectiveAudience == .group {
                await root.networkProxyStore.sendPlayer(data: model)
            }
        }
    }

    /// Called cross-file by the per-module `retryDeferredXReveals` helpers
    /// (Photo/Pdf/Space), so this stays internal rather than `private`.
    func sendUpstream(model: GameNetworkModel) async {
        if root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: false)
        }
    }
}
