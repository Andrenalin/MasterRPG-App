// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit

/// Physical dimensions (in meters) of the game table, shared by every
/// platform variant (visionOS TabletopKit table, iOS/macOS camera-based
/// table). Purely numeric with no platform dependency, so it's declared once
/// here instead of duplicated per platform file — see CODE_AUDIT §9.1.
enum GameMetrics {
    /// The table's X-axis extent — its long dimension, seating two players a
    /// side plus one at each end (see `PlayerSeat.seatPoses`).
    static let tableLength: Float = 2.0
    /// The table's Z-axis extent.
    static let tableWidth: Float = 1.5
    static let tableThickness: Float = 0.0146
    static let mapSurfaceClearance: Float = 0.0005
    /// Inset from the map's own edge (`MapTableProjection`'s fit-box) to the
    /// table's physical edge, on every side — leaves room for each seat's
    /// dice (`PlayerSeat.diceLayout`) between the map and the table's rim.
    static let mapMargin: Float = 0.25
    /// Inset from a seat's own near table edge to where its dice rest — see
    /// `PlayerSeat.diceLayout`.
    static let diceEdgeInset: Float = 0.06
    static let smallHeight: Float = 0.001
    static let boardHeight: Float = 0.055
    static let playerAreaSize = SIMD2<Float>(0.4, 0.1)
    static let playerHandSize = SIMD2<Float>(0.2, 0.1)
}

/// Marks the map surface's hit-test volume for `viewportPanGesture`
/// (`GameTableView`), so it can be targeted separately from pins and room
/// fog on every platform's `Board`. Shared here (rather than declared once
/// per platform's `Board`) so iOS/macOS and visionOS gesture code can target
/// the exact same component type. See CODE_AUDIT §8.1.
struct BoardSurfaceComponent: Component {}
#endif
