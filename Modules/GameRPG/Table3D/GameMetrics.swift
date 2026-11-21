// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit
import SwiftUI

/// Physical dimensions (in meters) of the game table, shared by every
/// platform variant (visionOS TabletopKit table, iOS/macOS camera-based
/// table). Purely numeric with no platform dependency, so it's declared once
/// here instead of duplicated per platform file.
enum GameMetrics {
    /// The table's Z-axis extent — its long dimension, seating two players a
    /// side plus one at each end (see `PlayerSeat.seatPoses`'s own doc for
    /// why the long dimension runs along Z rather than X).
    static let tableLength: Float = 2.0
    /// The table's X-axis extent — its short dimension.
    static let tableWidth: Float = 1.5
    static let tableThickness: Float = 0.0146
    static let mapSurfaceClearance: Float = 0.0005
    /// Inset from the map's own edge (`MapTableProjection`'s fit-box) to the
    /// table's physical edge, on every side — leaves room for each seat's
    /// dice (`PlayerSeat.diceLayout`) between the map and the table's rim.
    /// The dice lie `diceEdgeInset` from the rim and are at most `maximumDieExtent` across,
    /// so they reach `diceEdgeInset + maximumDieExtent / 2` into the table; the rest is slack
    /// for a die that settles a little off its slot.
    static let mapMargin: Float = 0.15
    /// The widest a die is (the d20, 3 to 3.75 cm; see `TableSeatDice.spacing`).
    static let maximumDieExtent: Float = 0.0375
    /// Inset from a seat's own near table edge to where its dice rest — see
    /// `PlayerSeat.diceLayout`.
    static let diceEdgeInset: Float = 0.06
    /// Half the height of a room's hit-test volume around pin height (`RoomHitArea`).
    static let roomHitHalfThickness: Float = 0.004
    /// Local Y offset of the map surface's hit-test box (`Board`), putting its whole height range
    /// clearly below `pinHeight - roomHitHalfThickness`, so a touch over a room's fog always hits the
    /// room volume first.
    static let boardHitTestYOffset: Float = -0.006
}

/// Marks the map surface's hit-test volume, so the board-drag gesture can target it separately from
/// pins and room fog. Shared so iOS/macOS and visionOS gesture code target the exact same component.
struct BoardSurfaceComponent: Component {}

/// Guard+dispatch shared by `GameTableView`'s visionOS (inline `RealityView` gesture) and
/// iOS/macOS (`pinDragGesture`) pin-drag handlers — both looked up the pin id and its
/// parent entity, then called `game.pinDragChanged`/`pinDragEnded`, differing only in how
/// `position` was derived: visionOS has a direct 3D touch location to convert, iOS/macOS
/// ray-casts a 2D touch onto the table plane (`tablePosition(relativeTo:)`). Each platform
/// supplies only that one difference as `resolvePosition`.
@MainActor
func withPinDragTarget(
    _ value: EntityTargetValue<DragGesture.Value>,
    position resolvePosition: (Entity) -> SIMD3<Float>?,
    perform action: (UUID, SIMD3<Float>) -> Void
) {
    guard let pinId = value.entity.components[PinComponent.self]?.pinId,
          let parent = value.entity.parent,
          let position = resolvePosition(parent) else { return }
    action(pinId, position)
}
#endif
