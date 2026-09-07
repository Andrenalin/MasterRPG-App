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
    // MARK: - GameToolBarSession

    /// Reflects the pointer pawn's real visibility rather than tracking a
    /// separate armed/disarmed flag — the 3D table has no mouse-follow
    /// concept the way the 2D map does, so "pointing" and "pointer visible"
    /// are the same thing here. `GameToolBar.togglePointingMode()` mutates
    /// the pointer directly through `MapRootModel`; this just reports the
    /// result, so the setter is a no-op.
    var isPointing: Bool {
        get { pointer?.isShown ?? false }
        set {}
    }

    var pinScale: CGFloat {
        get { currentMapModel()?.pinScale ?? 1 }
        set { currentMapModel()?.pinScale = newValue }
    }

    var hexScale: Double {
        get { currentMapModel()?.hexMapScale ?? 0 }
        set { currentMapModel()?.hexMapScale = newValue }
    }

    var isHexMap: Bool {
        rooms.contains(where: \.isHexGrid)
    }

    var canReshare: Bool {
        lastPinScale != pinScale
            || lastHexScale != hexScale
            || lastIsHexMap != isHexMap
    }

    func resetReshare() {
        lastPinScale = pinScale
        lastHexScale = hexScale
        lastIsHexMap = isHexMap
    }

    /// Toggles the hex overlay grid via the same `EditController` grid
    /// generation the 2D map editor uses (exposed publicly for this by
    /// `MapRootModel.toggleHexMap(itemId:)`), then re-syncs the board so the
    /// grid appears immediately.
    func toggleHexMap() {
        guard let mapId = currentMapId else { return }
        _ = mapRoot.toggleHexMap(itemId: mapId)
        syncAfterExternalEdit()
    }

    func sendMapUpdates() {
        guard let mapId = currentMapId else { return }
        broadcastMapState(for: mapId)
    }

    /// Game-master room action used by every tabletop platform.
    func toggleRoomVisibility(_ roomId: UUID) async {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.toggleRoom(itemId: mapId, roomId: roomId) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Toggles the same "focused" flag the 2D map's room long-press uses to
    /// zoom its own viewport to a room — keeping a concurrently open 2D map
    /// view in sync. Unlike the 2D map, the 3D board never crops/zooms into
    /// the focused room itself; it re-renders its fixed-size texture with
    /// just a red highlight border marking that room instead (see
    /// `boardFocusRect`).
    func toggleRoomFocus(_ roomId: UUID) async {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.toggleRoomFocus(itemId: mapId, roomId: roomId) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Shows or hides the full map with one render/sync/network transaction.
    func setAllRoomsShown(_ isShown: Bool) async {
        guard isGameMaster, let mapId = currentMapId else { return }
        let roomIds = rooms.map(\.id)
        guard mapRoot.mapGameControllable.setRoomsShown(
            itemId: mapId,
            roomIds: roomIds,
            isShown: isShown
        ) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    func togglePointerVisibility() {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.togglePointer(itemId: mapId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Places and reveals the pointer at the map center without requiring the
    /// 2D map window. Both mutations are delivered in one mapState message.
    func movePointerToMapCenter() {
        guard isGameMaster, let mapId = currentMapId, let mapModel = currentMapModel() else { return }
        let center = CGPoint(x: mapModel.width / 2, y: mapModel.height / 2)
        let moved = mapRoot.mapGameControllable.movePointer(itemId: mapId, location: center)
        let revealed = mapModel.pointer.isShown
            ? false
            : mapRoot.mapGameControllable.togglePointer(itemId: mapId)
        guard moved || revealed else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Adds a set selected by a future platform-specific character picker.
    /// Keeping the mutation here avoids coupling the tabletop to MapEditor.
    func addMonstersAtMapCenter(_ monsters: [ItemRowModel]) {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.addMonstersAtMapCenter(
                itemId: mapId,
                monsters: monsters
              ) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }
}

/// Lets the 3D table host the exact same `GameToolBar` (and its button
/// actions) as the 2D map — see `GameToolBarSession` for what this promises.
extension GameTableModel: GameToolBarSession {}

#endif
