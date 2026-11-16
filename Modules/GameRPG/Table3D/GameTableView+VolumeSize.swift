// @copyright André Trettin

#if os(visionOS)
import SwiftUI

extension GameTableView {
    /// How far back from the volume's front (near-viewer, +Z) face the table sits. The window's
    /// grab handle and the `.bottomFront` ornament are anchored to that face, so a small value
    /// keeps them at the table's edge. 15 cm, not `sideClearance`'s 1 cm: the master seat's tossed
    /// dice overshoot their resting place mid-toss, and 1, 5 and 10 cm all clipped them through
    /// the front bound on-device. Re-test an actual toss before tightening it. `public` for
    /// `WindowVisionList` in the app target.
    public static let frontClearance: Double = 0.15
    /// Clearance left on each side (X) of the table's footprint. Tight so the window's side handle
    /// sits at the table's edge; `TableScaleGestureController.maxScale` is tuned against this 1 cm.
    static let sideClearance: Double = 0.01
    /// Clearance beyond the table's footprint at the volume's back (far, -Z) edge. Nothing is
    /// anchored to the back edge, so it stays at the original table's 0.15 m.
    static let backClearance: Double = 0.15
    /// Height (m) of the volumetric window: headroom for a tossed die's arc, not the table's
    /// thickness. 0.3 m clipped the arc through the ceiling.
    static let volumeHeight: Double = 1.5

    /// Size (meters) of the volumetric window: the single source of truth for
    /// `WindowVisionList`'s `.defaultSize(...)` and `GameRenderer.rootOffset`'s depth. Width is
    /// the table's X-extent plus `sideClearance` per side; depth is its Z-extent plus the front
    /// and back clearances.
    public static var volumeSize: Size3D {
        Size3D(
            width: Double(GameMetrics.tableWidth) + sideClearance * 2,
            height: volumeHeight,
            depth: frontClearance + Double(GameMetrics.tableLength) + backClearance
        )
    }
}

#endif
