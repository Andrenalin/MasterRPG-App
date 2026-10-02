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

    /// Wires the model to the running game: the network, the game-master role and the player's
    /// own pin, plus the GM's preview lens, which a 2D↔3D toggle must keep (CODE_AUDIT_19 §5.17).
    /// Shared by the visionOS and iOS/macOS tables. See CODE_AUDIT_19 §9.14.
    func configureSession(from root: GameRoot) {
        networkActions = root.networkActions
        isGameMaster = root.gameModel.gameConfig.isMaster
        playerPinId = isGameMaster ? nil : root.gameModel.gameConfig.id
        if isGameMaster {
            displayMode = root.mapRoot.rootModel.gameDisplayMode
        }
#if os(visionOS)
        diceRoot = root.diceRoot
#endif
    }

    var pointer: MapPinModel? {
        currentMapModel()?.pointer
    }
}

#endif
