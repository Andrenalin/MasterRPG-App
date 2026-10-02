// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import Spatial

// The pure decisions behind the dice result popovers of the visionOS table, kept free of
// TabletopKit and RealityKit so they are unit-tested on iOS.

/// How a table die's synced value (`DieState.value`) is read. The value is all TabletopKit
/// shares about a die, so it also carries whether the die has been rolled.
enum TableDieValue {
    /// A pool slot that isn't part of its seat's focused dice set; the die is parked off-table.
    static let parked = 0
    /// A die of a focused set that has not been rolled yet. It lies with its 1 up, like a
    /// rolled 1, but shows no result.
    static let unrolled = -1

    static func isRolled(_ value: Int) -> Bool {
        value > 0
    }

    /// The face a die with this value shows on top.
    static func face(_ value: Int) -> Int {
        value == unrolled ? 1 : value
    }
}

/// Whether a die lies where its state says it belongs, as opposed to being carried, tossed
/// or still turning to a new face.
enum TableDiceRest {
    /// Positions closer than this count as arrived (metres).
    static let positionTolerance = 0.002
    /// Orientations closer than this count as arrived (radians).
    static let angleTolerance = 0.035
    /// How long a seat's dice must lie still before their result appears, so a die passing
    /// through its goal for a frame does not flash the popover.
    static let settleDuration: Duration = .milliseconds(250)

    static func isAtRest(pose: Pose3D, goal: Pose3D) -> Bool {
        let offset = pose.position - goal.position
        guard offset.length <= positionTolerance else { return false }
        // The same orientation as a quaternion and as its negative: compare by the angle
        // of the rotation between the two.
        let dot = abs(simd_dot(pose.rotation.quaternion.vector, goal.rotation.quaternion.vector))
        let angle = 2 * acos(min(1, dot))
        return angle <= angleTolerance
    }
}

/// Who sees which seat's dice result.
enum TableDiceResultVisibility {
    /// Players always see their own result and the game master sees every result this device
    /// has. Another seat's result follows the game's sharing options, which gate the same dice
    /// in the dice overlay: the master's dice and the other players' dice separately.
    static func isVisible(
        isLocalSeat: Bool,
        isGameMaster: Bool,
        isMasterSeat: Bool,
        features: GameFeatureModel
    ) -> Bool {
        if isLocalSeat || isGameMaster { return true }
        return isMasterSeat ? features.diceMaster : features.dicePlayers
    }
}
#endif
