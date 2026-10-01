// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import Combine
import DiceRPG
import TabletopKit
#endif

extension GameTableModel {
    // MARK: - Broadcast Helpers

    func mapModel(for mapId: UUID) async -> MapModel? {
        if let liveMap = mapRoot.mapGameControllable.gameModel.itemData[mapId] as? MapModel {
            return liveMap
        }
        return await mapRoot.itemControllable.item(for: mapId) as? MapModel
    }

    func currentMapModel() -> MapModel? {
        guard let currentMapId else { return nil }
        return (mapRoot.mapGameControllable.gameModel.itemData[currentMapId] as? MapModel)
            ?? (mapRoot.itemControllable.itemSync(for: currentMapId) as? MapModel)
    }

    func photoMetadata(for photoId: UUID) -> (version: Int, degrees: Double)? {
        let photo = (photoRoot.gameControllable.gameModel.itemData[photoId] as? PhotoModel)
            ?? (photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel)
        guard let photo else { return nil }
        return (photo.version, photo.degrees)
    }

    func clearBoardImage() {
        currentPhotoId = nil
        currentPhotoVersion = nil
        currentMapImage = nil
        currentMapDegrees = 0
        fogSignature = nil
        boardRenderGeneration += 1
        setup.board.clearMap()
    }

    /// Broadcasts a game-master edit unless the GM paused sharing (`isStreaming`). Every GM
    /// mutation must go through here so hidden rooms/pins never reach players while sharing is
    /// paused; only the explicit "Refresh Shared Map" (`sendMapUpdates`) bypasses the pause.
    func broadcastMapEdit(for mapId: UUID) {
        guard isStreaming else { return }
        // A pending content update ends with a live map state that includes this edit.
        guard pendingMapContentBroadcasts[mapId, default: 0] == 0 else { return }
        broadcastMapState(for: mapId)
    }

    /// A structural edit (entries added/removed, e.g. the hex grid) needs the content update
    /// first — a map state that references entries a player doesn't have forces every player
    /// through a repair round trip — then the map state. Honours "pause sharing" like
    /// `broadcastMapEdit`: while paused the map is marked, and the resume/refresh send
    /// (`sendMapUpdates`) pushes the content update. See CODE_AUDIT_18 §5.19, CODE_AUDIT_19 §3.12.
    func broadcastMapContentEdit(for mapId: UUID) {
        guard isStreaming else {
            mapRoot.rootModel.mapsWithUnsharedStructure.insert(mapId)
            return
        }
        sendMapContent(for: mapId, force: false)
    }

    /// Sends the map's content update, then its live map state, chained (on the map root's shared
    /// chain) behind any earlier content update so two quick structural edits arrive in order. `force` bypasses the
    /// pause, for the explicit "Refresh Shared Map".
    func sendMapContent(for mapId: UUID, force: Bool) {
        let mapRoot = mapRoot
        let rootModel = mapRoot.rootModel
        pendingMapContentBroadcasts[mapId, default: 0] += 1
        rootModel.enqueueMapContentSend { [weak self] in
            let content = await mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
            guard let self else {
                // The table model was released (a 2D↔3D toggle) while the update was
                // pending: the structural change must still reach the players on the next
                // explicit send. See CODE_AUDIT_20 §3.1.
                rootModel.mapsWithUnsharedStructure.insert(mapId)
                return
            }
            self.pendingMapContentBroadcasts[mapId, default: 1] -= 1
            if self.pendingMapContentBroadcasts[mapId] == 0 {
                self.pendingMapContentBroadcasts[mapId] = nil
            }
            guard force || self.isStreaming else {
                self.mapRoot.rootModel.mapsWithUnsharedStructure.insert(mapId)
                return
            }
            self.networkActions?.game(content, .generic, nil)
            self.broadcastMapState(for: mapId)
        }
    }

    func broadcastMapState(for mapId: UUID) {
        networkActions?.game(
            mapRoot.mapGameControllable.networkMapUpdate(for: mapId),
            .mapState,
            nil
        )
    }

    func broadcastBattleRoundState(for mapId: UUID) {
        guard let battleUpdate = mapRoot.mapGameControllable.networkBattleRoundUpdate(
            for: mapId
        ) else {
            return
        }
        networkActions?.game(battleUpdate, .battleRound, nil)
    }

    func sendPlayerPinUpdate(mapId: UUID, pinId: UUID) {
        guard let pinData = mapRoot.mapGameControllable.networkPin(
            itemId: mapId,
            pinId: pinId
        ) else { return }
        networkActions?.game(pinData, .mapPin, nil)
    }

    func sendPlayerPointerUpdate(mapId: UUID) {
        guard let pointerData = mapRoot.mapGameControllable.networkPointer(itemId: mapId) else { return }
        networkActions?.game(pointerData, .mapPin, nil)
    }
}

#endif
