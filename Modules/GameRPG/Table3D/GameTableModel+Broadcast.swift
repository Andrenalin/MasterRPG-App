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
        broadcastMapState(for: mapId)
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
