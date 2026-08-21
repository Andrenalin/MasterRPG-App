// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import MapRPG

private enum PlayerMapPinApplication: Sendable {
    case applied
    case awaitingMapGeneration
    case rejected
}

extension PlayerController {
    func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let isPlayerMapPin = model.sender.role == .player &&
            model.type == .update &&
            model.subType == .mapPin &&
            model.data.type == .map &&
            model.effectiveAudience == .group
        if isPlayerMapPin {
            switch applyPlayerMapPin(model) {
            case .applied, .rejected:
                break
            case .awaitingMapGeneration:
                gameModel.deferMapPin(model)
            }
            return nil
        }

        guard model.sender.isMaster else { return nil }

        if root.gameModel.gameConfig.isMaster {
            // The game master's own co-located screen (and any external
            // display reading the same state) is always seeing its own
            // broadcast here: master and player share one `GameRoot`, so
            // `model.data` merely echoes state this device's `root.mapRoot`
            // already holds as the single source of truth. None of the
            // asset/content-generation matching, import, or repair
            // machinery below is meaningful when sender and receiver are
            // literally the same object — just present it.
            return await handleLocalMasterMap(model)
        }

        switch model.type {
        case .reveal:
            let isRepairPayload = model.targetId != nil || model.subType == .store
            if !isRepairPayload,
               model.data.data != nil,
               let pending = gameModel.pendingMapRepairRequirement(itemId: model.data.id),
               !gameModel.pendingMapRepairMatches(model.data),
               model.counter > pending.counter {
                // A newer ordinary show is a fresh authoritative intent, not an
                // answer to the older request. Replace the queued repair so its
                // stale state/content cannot be applied to the new generation.
                gameModel.supersedeMapRepair(itemId: model.data.id)
            }
            if isRepairPayload {
                guard gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil,
                      gameModel.pendingMapRepairMatches(model.data)
                else { return nil }
            }

            let hasBaseMap = await root.mapRoot.gameControllable.hasItem(
                id: model.data.id,
                version: 0
            )
            let hasMatchingAsset: Bool
            if hasBaseMap, model.data.assetVersion != nil {
                hasMatchingAsset = await hasMatchingMapAsset(model.data)
            } else {
                hasMatchingAsset = false
            }
            let shouldImportFullPayload: Bool
            if model.data.data == nil {
                shouldImportFullPayload = true
            } else {
                shouldImportFullPayload = gameModel.shouldImportFullMapContent(
                    itemId: model.data.id,
                    counter: model.counter
                )
            }
            let revealed: Bool
            if model.data.data != nil, model.data.assetVersion != nil {
                if hasBaseMap, !shouldImportFullPayload {
                    // A newer full/photo-free update already won. Keep its
                    // metadata while honoring this reveal only when the local
                    // background is the exact advertised asset generation.
                    revealed = hasMatchingAsset
                } else {
                    // Current-protocol full payloads carry independent asset and
                    // content fingerprints. Always import a newly sequenced one:
                    // the background may have changed without the legacy scale
                    // version changing, or its structural snapshot may be newer
                    // even though the background still matches.
                    do {
                        // The master is unconditionally authoritative for map
                        // state — `.overwrite` skips the default CRDT
                        // last-writer-wins merge, which is keyed on each
                        // device's own local wall clock and can otherwise let
                        // this player's own stale, previously-persisted copy
                        // of the map silently win over what the master just
                        // broadcast (discarding e.g. a just-updated pin
                        // healthPercent with no error). See
                        // player-character-sync-gaps memory note.
                        try await root.mapRoot.gameControllable.updateGame(
                            data: model.data,
                            hide: true,
                            deep: false,
                            importMode: .overwrite
                        )
                    } catch {
                        Logger.networking.error("PlayerController: Failed to import full map payload \(model.data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                    // Importing the map package establishes the advertised
                    // generation even when its background bytes are not locally
                    // readable. Background readiness is checked independently
                    // before presentation and acknowledgement below.
                    await recordImportedFullMapGeneration(model)
                    revealed = await hasMatchingMapAsset(model.data)
                }
            } else if model.data.data == nil, model.data.assetVersion != nil {
                // Mutable map metadata may have changed while the background
                // asset stayed the same. Current peers can reuse that asset and
                // wait for the companion mapUpdate; legacy peers still follow
                // the original scale-version comparison in reveal().
                // A reference for a different background asset must request the
                // full Journal/messenger package even when the legacy scale-only
                // `version` still matches the local MapModel.
                revealed = hasMatchingAsset
            } else {
                do {
                    revealed = try await root.mapRoot.gameControllable.reveal(
                        itemId: model.data.id,
                        data: model.data,
                        save: false
                    )
                } catch {
                    Logger.networking.error("PlayerController: Failed to reveal map \(model.data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
                if revealed, model.data.data != nil {
                    await recordImportedFullMapGeneration(model)
                }
            }

            guard revealed else {
                gameModel.clearGameUpdateTypeIfPhoto()
                guard !isRepairPayload else { return nil }
                return await requestFullMap(
                    for: model,
                    requestType: .reveal,
                    action: model.subType,
                    presentsMap: true
                )
            }

            _ = await applyPendingMapContentUpdate(itemId: model.data.id)

            // A metadata-only reveal is complete only when both independent
            // generations are locally available. Missing a structural update is
            // repaired exactly once for that advertised content fingerprint.
            if model.data.data == nil,
               !gameModel.hasMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion
               ) {
                return await requestMapContent(
                    for: model,
                    presentsMap: true
                )
            }

            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) else {
                // Never ACK or present an unusable Map. One retry per exact
                // asset/content generation bounds a permanently broken export.
                return await requestFullMap(
                    for: model,
                    requestType: .reveal,
                    action: model.subType == .store ? .mapState : model.subType,
                    presentsMap: true,
                    backgroundRetry: true
                )
            }

            _ = await applyPendingMapState(itemId: model.data.id)
            let hadPendingRepair = gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil
            let completedRepair = await completeMapRepairIfSatisfied(itemId: model.data.id)
            guard !hadPendingRepair || completedRepair != nil else { return nil }
            await presentMap(itemId: model.data.id)
            return await response(for: model, isSuccess: true, requestData: false)

        case .store:
            guard model.data.data != nil else { return nil }
            if gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil,
               !gameModel.pendingMapRepairMatches(model.data) {
                return nil
            }

            let hasBaseMap = await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0)
            let shouldImport = gameModel.shouldImportFullMapContent(
                itemId: model.data.id,
                counter: model.counter
            )
            var importedFullPayload = false
            if !hasBaseMap || shouldImport {
                do {
                    // See the matching comment on the `.reveal` branch above —
                    // the master is unconditionally authoritative for map
                    // state, so this skips the default CRDT merge too.
                    try await root.mapRoot.gameControllable.updateGame(
                        data: model.data,
                        hide: true,
                        deep: true,
                        importMode: .overwrite
                    )
                } catch {
                    Logger.networking.error("PlayerController: Failed to import full map payload \(model.data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
                importedFullPayload = true
                root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(
                    model.data
                )
                gameModel.recordFullMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion,
                    counter: model.counter
                )
            } else if await !hasMatchingMapAsset(model.data) {
                return nil
            }

            _ = await applyPendingMapContentUpdate(itemId: model.data.id)
            _ = await applyPendingMapState(itemId: model.data.id)
            retryDeferredMapPins(itemId: model.data.id)
            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) else {
                return await requestFullMap(
                    for: model,
                    requestType: .store,
                    action: .store,
                    presentsMap: false,
                    backgroundRetry: true
                )
            }

            let hadPendingRepair = gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil
            let completesPresentation = await completeMapRepairIfSatisfied(itemId: model.data.id)
            guard !hadPendingRepair || completesPresentation != nil else { return nil }
            if completesPresentation == true {
                await presentMap(itemId: model.data.id)
            } else if importedFullPayload {
                await requestMissingMapImages(itemId: model.data.id)
            }
            return await response(for: model, isSuccess: true, requestData: false)

        case .update:
            switch model.subType {
            case .generic:
                return await handleMapContentUpdate(model)
            case .mapState:
                guard gameModel.shouldApplyMapState(
                        itemId: model.data.id,
                        counter: model.counter
                      )
                else { return nil }

                let hasBaseMap = await root.mapRoot.gameControllable.hasItem(
                    id: model.data.id,
                    version: 0
                )
                let hasMatchingAsset = await hasMatchingMapAsset(model.data)
                let hasMatchingContent = gameModel.hasMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion
                )
                guard hasBaseMap, hasMatchingAsset else {
                    gameModel.queueMapState(model.data, counter: model.counter)
                    return await requestFullMap(
                        for: model,
                        requestType: .reveal,
                        action: .mapState,
                        presentsMap: true
                    )
                }
                guard hasMatchingContent else {
                    gameModel.queueMapState(model.data, counter: model.counter)
                    return await requestMapContent(for: model, presentsMap: true)
                }

                guard root.mapRoot.mapGameControllable.updateMap(
                    for: model.data.id,
                    with: model.data
                ) else { return nil }
                gameModel.markMapStateApplied(itemId: model.data.id, counter: model.counter)
                _ = await completeMapRepairIfSatisfied(itemId: model.data.id)
                retryDeferredMapPins(itemId: model.data.id)
                gameModel.setGameUpdateType(.map)
                await refreshMapVisuals(itemId: model.data.id)

            case .mapPin:
                // Player pin events are handled before the master-only switch.
                return nil
            case .battleRound:
                guard root.mapRoot.mapGameControllable.applyBattleRoundUpdate(
                    for: model.data.id,
                    with: model.data
                ) else { return nil }
                setMapUpdateTypeAndSyncPawns()
            default:
                return nil
            }
        }
        return nil
    }

    /// Handles every Map message `handleMap` routes here because
    /// `root.gameModel.gameConfig.isMaster` is true — i.e. this
    /// `PlayerController` is the game master's own co-located mirror,
    /// talking to itself. `root.mapRoot` is this device's single source of
    /// truth for the map regardless of any message describing it, so this
    /// never imports, compares generations, or requests a repair: it only
    /// ever updates this controller's own presentation bookkeeping
    /// (`gameUpdateType`, the current map, visuals) to match what the
    /// master already broadcast.
    private func handleLocalMasterMap(_ model: GameNetworkModel) async -> GameNetworkModel? {
        switch model.type {
        case .reveal, .store:
            await presentMap(itemId: model.data.id)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .mapState:
                retryDeferredMapPins(itemId: model.data.id)
                gameModel.setGameUpdateType(.map)
                await refreshMapVisuals(itemId: model.data.id)
            case .battleRound:
                setMapUpdateTypeAndSyncPawns()
            case .generic, .mapPin:
                // A structural/content resync or a player-authored pin move:
                // this device's own map already reflects it. Neither one is
                // a presentation intent on its own (`.generic` in particular
                // must not force the map to the front over whatever the
                // master currently has shown, e.g. a Photo).
                break
            default:
                break
            }
            return nil
        }
    }

    func handleMapContentUpdate(_ model: GameNetworkModel) async -> GameNetworkModel? {
        guard model.sender.isMaster,
              model.data.type == .map,
              model.data.data != nil
        else { return nil }
        guard gameModel.shouldApplyMapContentUpdate(
            itemId: model.data.id,
            counter: model.counter
        ) else { return nil }

        let hasBaseMap = await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0)
        let hasMatchingAsset = await hasMatchingMapAsset(model.data)
        guard hasBaseMap, hasMatchingAsset else {
            gameModel.queueMapContentUpdate(model.data, counter: model.counter)
            return await requestFullMap(
                for: model,
                requestType: .reveal,
                action: .mapState,
                presentsMap: false
            )
        }

        guard root.mapRoot.mapGameControllable.applyMapContentUpdate(
            for: model.data.id,
            with: model.data
        ) else { return nil }
        gameModel.markMapContentUpdateApplied(
            itemId: model.data.id,
            counter: model.counter,
            contentVersion: model.data.contentVersion
        )
        _ = await applyPendingMapState(itemId: model.data.id)
        retryDeferredMapPins(itemId: model.data.id)
        let completesPresentation = await completeMapRepairIfSatisfied(itemId: model.data.id)
        if completesPresentation == true {
            await presentMap(itemId: model.data.id)
        } else if let pending = gameModel.pendingMapRepairRequirement(itemId: model.data.id),
                  await !root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) {
            return await requestFullMap(
                for: model,
                requestType: .reveal,
                action: .mapState,
                presentsMap: pending.presentsMap,
                backgroundRetry: true
            )
        } else {
            await refreshMapVisuals(itemId: model.data.id)
        }
        return nil
    }

    func applyPendingMapContentUpdate(itemId: UUID) async -> Bool {
        guard let pending = gameModel.pendingMapContentUpdate(for: itemId) else { return false }
        guard gameModel.shouldApplyMapContentUpdate(
            itemId: itemId,
            counter: pending.counter
        ) else {
            gameModel.discardPendingMapContentUpdate(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              root.mapRoot.mapGameControllable.applyMapContentUpdate(
                for: itemId,
                with: pending.data
              )
        else { return false }

        gameModel.markMapContentUpdateApplied(
            itemId: itemId,
            counter: pending.counter,
            contentVersion: pending.data.contentVersion
        )
        return true
    }

    func applyPendingMapState(itemId: UUID) async -> Bool {
        guard let pending = gameModel.pendingMapState(for: itemId) else { return false }
        guard gameModel.shouldApplyMapState(itemId: itemId, counter: pending.counter) else {
            gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              gameModel.hasMapContentVersion(
                itemId: itemId,
                contentVersion: pending.data.contentVersion
              )
        else { return false }

        guard root.mapRoot.mapGameControllable.updateMap(
            for: itemId,
            with: pending.data
        ) else {
            gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        gameModel.markMapStateApplied(itemId: itemId, counter: pending.counter)
        return true
    }

    func hasMatchingMapAsset(_ data: NetworkCodableDataType) async -> Bool {
        guard let expectedAssetVersion = data.assetVersion else { return true }
        return await root.mapRoot.mapGameControllable.mapAssetVersion(for: data.id) == expectedAssetVersion
    }

    func recordImportedFullMapGeneration(_ model: GameNetworkModel) async {
        root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(
            model.data
        )
        gameModel.recordFullMapContentVersion(
            itemId: model.data.id,
            contentVersion: model.data.contentVersion,
            counter: model.counter
        )
    }

    func completeMapRepairIfSatisfied(itemId: UUID) async -> Bool? {
        guard let requirement = gameModel.pendingMapRepairRequirement(itemId: itemId) else {
            return nil
        }
        if let expectedAssetVersion = requirement.assetVersion,
           await root.mapRoot.mapGameControllable.mapAssetVersion(for: itemId) != expectedAssetVersion {
            return nil
        }
        guard gameModel.hasMapContentVersion(
            itemId: itemId,
            contentVersion: requirement.contentVersion
        ), await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: itemId) else {
            return nil
        }
        return gameModel.completeMapRepair(itemId: itemId)
    }

    func requestFullMap(
        for model: GameNetworkModel,
        requestType: RPGMessageType,
        action: RPGMessageActionType,
        presentsMap: Bool,
        backgroundRetry: Bool = false
    ) async -> GameNetworkModel? {
        let shouldRequest = if backgroundRetry {
            gameModel.beginMapBackgroundRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        } else {
            gameModel.beginMapRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        }
        guard shouldRequest else { return nil }

        return root.gameModel.outgoingMessage(
            replyToMessageID: model.messageID,
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: requestType,
            subType: action,
            asMaster: false,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: model.data.id,
                type: .map,
                version: model.data.version,
                data: nil,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion
            )
        )
    }

    func requestMapContent(
        for model: GameNetworkModel,
        presentsMap: Bool
    ) async -> GameNetworkModel? {
        guard gameModel.beginMapRepair(
            itemId: model.data.id,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion,
            presentsMap: presentsMap,
            counter: model.counter
        ) else { return nil }

        return root.gameModel.outgoingMessage(
            replyToMessageID: model.messageID,
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: .update,
            subType: .generic,
            asMaster: false,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: model.data.id,
                type: .map,
                version: model.data.version,
                data: nil,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion
            )
        )
    }

    func presentMap(itemId: UUID) async {
        _ = await root.mapRoot.gameControllable.setCurrent(itemId: itemId)
        if root.gameModel.gameConfig.isMaster {
            _ = root.mapRoot.mapGameControllable.synchronizePlayerPins(for: itemId)
            // Pin reconciliation just above can change this map's structural
            // content right after this reveal recorded its generation's
            // fingerprint. Refresh it so the game master's own co-located
            // screen keeps recognizing this exact, unedited map on a later
            // reference-only reshow instead of chasing a phantom repair.
            root.mapRoot.mapGameControllable.refreshAuthoritativeMapContentVersion(for: itemId)
        }
        retryDeferredMapPins(itemId: itemId)
        gameModel.setGameUpdateType(.map)
        await refreshMapVisuals(itemId: itemId)
    }

    private func applyPlayerMapPin(_ model: GameNetworkModel) -> PlayerMapPinApplication {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == model.data.id else {
            return .awaitingMapGeneration
        }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id)
        guard model.data.version == generation.version,
              model.data.assetVersion == generation.assetVersion,
              model.data.contentVersion == generation.contentVersion
        else {
            return .awaitingMapGeneration
        }
        guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
            itemId: model.data.id,
            data: model.data,
            playerId: model.sender.id
        ) else {
            return .rejected
        }

        // Runs on every device that mirrors this `.mapPin` broadcast — a
        // player device included. Only the master may let this recompute/
        // persist `pin.healthPercent`; on a player's own device it's a
        // guaranteed no-op (see `synchronizeBattleDefenders`'s doc comment).
        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
            itemId: model.data.id,
            isGameMaster: root.gameModel.gameConfig.isMaster
        )
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        return .applied
    }

    private func retryDeferredMapPins(itemId: UUID) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == itemId else { return }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
        let deferred = gameModel.consumeDeferredMapPins(for: itemId, matching: generation)
        var didApplyPin = false
        for model in deferred {
            didApplyPin = root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: itemId,
                data: model.data,
                playerId: model.sender.id
            ) || didApplyPin
        }
        guard didApplyPin else { return }

        // Same reasoning as `applyPlayerMapPin` above: a no-op unless this
        // device is the master.
        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
            itemId: itemId,
            isGameMaster: root.gameModel.gameConfig.isMaster
        )
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    func refreshMapVisuals(itemId: UUID) async {
        // mapState carries pin metadata but not newly referenced photo models.
        // The background itself remains exclusive to the full Map package.
        await requestMissingMapImages(itemId: itemId)
        #if !os(tvOS)
        let isGameMaster = root.gameModel.gameConfig.isMaster
        await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    /// Requests pin photos absent from both the photo game state and persistent
    /// item controller. The map background is delivered with the full map.
    /// Each photo is requested once per connection; SharePlay turns the first
    /// full answer into one group store so peers do not transfer it again.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingMapImages(itemId: itemId)
        for idType in missingImages {
            let isFirstRequest = gameModel.insertRequestedRepairId(idType.id)
            guard isFirstRequest else { continue }
            await send(
                type: .store,
                subType: .store,
                updated: idType,
                relayToProxyClients: false,
                purpose: .assetRequest
            )
        }
    }
}
