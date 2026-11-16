// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import RealityKit
import RPGTabletopGameContent
import Spatial
import TabletopKit
import UIKit
import os.log

// MARK: - Shared Assets

/// Loads each bundled roll sound once and hands out the shared resource. Every seat pre-allocates a
/// pool of dice (`GameSetup.maxDicePerType` per type, per seat), so loading per die meant dozens of
/// identical synchronous disk loads on the main actor when the table opened. The dice themselves
/// have no assets: their meshes and textures are generated in code (`GameDie*.swift`).
@MainActor
enum DieAssets {
    private static var audioResources: [String: AudioFileResource] = [:]

    static func audio(named path: String) throws -> AudioFileResource {
        if let resource = audioResources[path] {
            return resource
        }
        let resource = try AudioFileResource.load(
            named: path,
            from: "dice_sounds.usda",
            in: tabletopGameContentBundle
        )
        audioResources[path] = resource
        return resource
    }
}

// MARK: - Dice Accessibility

/// Identifies a die entity for VoiceOver's accessibility "activate" gesture
/// — see `GameTableModel.tossDieForAccessibility`. Mirrors `PinComponent`/
/// `RoomComponent`, but on `Die20`/`Die` themselves (TabletopKit equipment,
/// not a plain entity), rather than on a wrapper class.
struct DiceComponent: Component {
    let dieId: EquipmentIdentifier
    let sides: Int
}

/// Off-table park position for a pool die that is not part of any seat's focused set: every die's
/// initial pose, and reapplied by `GameTableModel.applyDiceRoll` when a slot leaves the focused set.
///
/// Dice are parked by their synced pose, never by `Entity.isEnabled`: a permanently disabled die
/// was never registered as static equipment on a joining player's device, and the first snapshot
/// read of one crashed with "Could not find static equipment with identifier: ...". Far outside the
/// table surface and every seat position, so a parked die never overlaps a claimed seat.
extension TableVisualState.Pose2D {
    static var parkedDicePose: Self {
        .init(position: .init(x: -5, z: -5), rotation: .zero)
    }
}
#endif
