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
        set {
            currentMapModel()?.pinScale = newValue
            // Token sizes derive from `pinScale` in `syncPins`, and nothing else observes it.
            syncPawnsWithMapPins()
        }
    }

    var hexScale: Double {
        get { pendingHexScale ?? currentMapModel()?.hexMapScale ?? 0 }
        set { pendingHexScale = newValue }
    }

    /// Applies the scale the slider was released at. On a hex map the grid is rebuilt for it,
    /// with the revealed area kept; the scale alone used to be stored and the grid stayed as it
    /// was. See CODE_AUDIT_21 §5.19.
    func commitHexScale() {
        guard let scale = pendingHexScale else { return }
        pendingHexScale = nil
        guard let map = currentMapModel(), scale != map.hexMapScale else { return }
        guard isHexMap else {
            map.hexMapScale = scale
            return
        }
        // Game-master only, like `toggleHexMap()`.
        guard isGameMaster, scale != 0, let mapId = currentMapId else { return }
        mapRoot.rescaleHexMap(itemId: mapId, scale: scale)
        replaceFogOfWarTask()
        syncPawnsWithMapPins()
        broadcastMapContentEdit(for: mapId)
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
        // Game-master only, like the sibling toolbar actions: a player must never edit its own
        // game copy of the map. See CODE_AUDIT_18 §5.19.
        guard isGameMaster, let mapId = currentMapId else { return }
        _ = mapRoot.toggleHexMap(itemId: mapId)
        // Re-render the board: it draws every entry, including the hex grid, which otherwise
        // stayed stale until an unrelated fog change. See CODE_AUDIT_17 §5.24.
        replaceFogOfWarTask()
        syncPawnsWithMapPins()
        // The new/removed hex entries go out as a structural content update before the map
        // state. See CODE_AUDIT_18 §5.19.
        broadcastMapContentEdit(for: mapId)
    }

    func sendMapUpdates() {
        guard let mapId = currentMapId else { return }
        // A structural edit made while sharing was paused was never sent. See CODE_AUDIT_19 §3.12.
        if mapRoot.rootModel.mapsWithUnsharedStructure.remove(mapId) != nil {
            sendMapContent(for: mapId, force: true)
        } else {
            broadcastMapState(for: mapId)
        }
    }

    /// Game-master room action used by every tabletop platform.
    func toggleRoomVisibility(_ roomId: UUID) async {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.toggleRoom(itemId: mapId, roomId: roomId) else { return }
        await replaceFogOfWarTask().value
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
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
        await replaceFogOfWarTask().value
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }
}

/// Lets the 3D table host the exact same `GameToolBar` (and its button
/// actions) as the 2D map — see `GameToolBarSession` for what this promises.
extension GameTableModel: GameToolBarSession {}

#endif
