// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import MapRPG

// Split out of PlayerController+Map.swift — presentation, pin and
// battle-round application. See CODE_AUDIT_Game §9.9.

extension PlayerController {
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
        retryDeferredBattleRoundUpdate(itemId: itemId)
        gameModel.setGameUpdateType(.map)
        await refreshMapVisuals(itemId: itemId)
    }

    /// Applies a pin another player moved, when it is for the map this device shows in the
    /// generation it holds. A pin for anything else is dropped: the game master's next map
    /// state carries every pin.
    func applyPlayerMapPin(_ model: GameNetworkModel) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == model.data.id else { return }
        guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
            itemId: model.data.id,
            data: model.data,
            playerId: model.sender.id
        ) else { return }

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
    }

    /// Replays a `.battleRound` update that arrived before its map. `applyBattleRoundUpdate`
    /// itself re-validates the generation and the state's own sequence number before applying
    /// anything. See CODE_AUDIT §5.2.
    func retryDeferredBattleRoundUpdate(itemId: UUID) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == itemId,
              let data = gameModel.pendingBattleRoundUpdate(for: itemId) else { return }
        guard root.mapRoot.mapGameControllable.applyBattleRoundUpdate(for: itemId, with: data) else { return }
        gameModel.discardPendingBattleRoundUpdate(itemId: itemId)
        setMapUpdateTypeAndSyncPawns()
    }

    func refreshMapVisuals(itemId: UUID) async {
        // mapState carries pin metadata but not newly referenced photo models.
        // The background itself remains exclusive to the full Map package.
        await requestMissingMapImages(itemId: itemId)
        #if !os(tvOS)
        let isGameMaster = root.gameModel.gameConfig.isMaster
        await root.gameModel.gameTableModel?.refreshFogOfWar(isGameMaster: isGameMaster)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    /// Asks for the pin photos this device holds neither in the photo game state nor in its
    /// library. The background is part of the map package. Each photo is asked for once per
    /// connection.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingMapImages(itemId: itemId)
        for idType in missingImages {
            guard gameModel.insertRequestedPinPhotoId(idType.id) else { continue }
            // No master message named this photo, so the request has no counter to echo.
            await send(
                counter: 0,
                type: .store,
                subType: .store,
                updated: idType.reference,
                relayToProxyClients: false
            )
        }
    }
}
