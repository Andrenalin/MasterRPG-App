// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit

extension GameTableModel {
    // MARK: - Rooms & Board State

    /// Unlike the 2D map's room-focus zoom, the 3D board never crops or zooms into a focused room:
    /// its fixed-size surface makes a fill-and-clip crop disorienting. A focused room instead gets a
    /// red highlight border at full scale (see `BoardTextureRenderer`).
    var rooms: [MapEntryModel] {
        currentMapModel()?.entries ?? []
    }

    /// The room the game master currently has focused, mirroring the 2D map's own notion of a focus
    /// room. Used by the shared `ChooseMapPinsButton` toolbar control to know where a newly added
    /// monster pin should land.
    var focusedRoomId: UUID? {
        rooms.first(where: \.focused)?.id
    }

    /// Re-syncs pawns and re-broadcasts after a map mutation made outside this model — e.g.
    /// `ChooseMapPinsButton` adding monster pins directly through `EditController`, bypassing this
    /// model's own mutation methods (which all sync/broadcast themselves). Local sync always runs so
    /// the game master sees the change immediately; broadcasting respects `isStreaming`.
    func syncAfterExternalEdit() {
        syncPawnsWithMapPins()
        guard isGameMaster, let mapId = currentMapId else { return }
        broadcastMapEdit(for: mapId)
    }

    var pointer: MapPinModel? {
        currentMapModel()?.pointer
    }
}

#endif
