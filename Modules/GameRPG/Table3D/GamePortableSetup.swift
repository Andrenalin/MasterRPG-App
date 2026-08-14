// @copyright André Trettin

#if os(iOS) || os(macOS)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import os.log

@MainActor
final class GameSetup {
    let root: Entity
    let board: Board
    let pinContainer: Entity
    /// Container for invisible room fog hit-test volumes, parallel to `pinContainer`.
    let roomHitContainer: Entity
    var pinPawns: [PinPawn] = []
    var roomHitAreas: [RoomHitArea] = []

    init(root: Entity) {
        self.root = root
        PinComponent.registerComponent()
        RoomComponent.registerComponent()
        BoardSurfaceComponent.registerComponent()

        board = Board()
        root.addChild(board.entity)

        pinContainer = Entity()
        pinContainer.name = "PinContainer"
        root.addChild(pinContainer)

        roomHitContainer = Entity()
        roomHitContainer.name = "RoomHitContainer"
        root.addChild(roomHitContainer)
    }
}
#endif
