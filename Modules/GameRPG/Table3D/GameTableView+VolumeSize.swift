// @copyright André Trettin

#if os(visionOS)
import SwiftUI

extension GameTableView {
    /// How far back from the volumetric window's front (near-viewer, +Z)
    /// face the table sits — feeds `GameRenderer.rootOffset`'s placement
    /// math (see that property's own doc). Tightened from an earlier 0.5 m
    /// held purely for viewer comfort (so the table wouldn't land right at
    /// the volume's near clipping bound when the window opens), which also
    /// left the window's system grab handle and this view's own
    /// `.bottomFront` ornament — both
    /// anchored to that same front face — sitting a visible ~0.5 m off the
    /// table's actual edge. 1 cm (matching `sideClearance`), 5 cm, and 10 cm
    /// all still clipped on-device — not the table mesh itself (a plain,
    /// bounding-box-exact box, see `TableAssetFactory.makePlainWoodTable()`),
    /// but the master (South) seat's own tossed dice: `PlayerSeat.diceLayout`
    /// already rests them only ~6 cm inside the table's own front edge
    /// (`GameMetrics.diceEdgeInset`), and a toss's physics carries them
    /// further forward, transiently, before they settle — with less than
    /// 15 cm of margin that overshoot clipped straight through the volume's
    /// front bound and made the die vanish mid-toss. Confirmed working
    /// on-device at 15 cm; don't retighten this without re-testing an actual
    /// dice toss (a static screenshot of the table at rest won't show the
    /// problem). Declared here, not in `GameRenderer` itself, so it shares
    /// one definition with `volumeSize` below instead of two files each
    /// hardcoding the same literal. `public` — read from `WindowVisionList`,
    /// in the app target rather than this module.
    public static let frontClearance: Double = 0.15
    /// Clearance left on each side (X) of the table's own footprint —
    /// deliberately tight (not `backClearance`'s 0.15 m) so the leading/
    /// trailing window handle sits right at the table's edge instead of the ~0.3 m gap the old `tableLength`-derived width left.
    /// `TableScaleGestureController.maxScale` is tuned against this same
    /// 1 cm budget — see its own doc before widening this back out.
    static let sideClearance: Double = 0.01
    /// Clearance left beyond the table's own footprint at the volume's back
    /// (far, −Z) edge — mirrors the ~0.15 m the original 0.7 m square table
    /// used, carried forward unchanged since. Not tightened alongside
    /// `sideClearance`/`frontClearance`: nothing is anchored to the back
    /// edge the way the handle/ornaments are to the sides and front.
    static let backClearance: Double = 0.15
    /// Fixed height (m) of the volumetric window — headroom for a tossed
    /// die's return-to-place arc (see `GameRenderer.placeTable(bottomY:)`),
    /// not derived from the table's own ~0.03 m thickness. An earlier 0.3 m
    /// value was tall enough for the static table but clipped a tossed
    /// die's upward arc through the volume's ceiling mid-animation.
    static let volumeHeight: Double = 1.5

    /// Fixed size (in meters) of the volumetric window this table renders
    /// inside — the single source of truth for `WindowVisionList`'s
    /// `.defaultSize(...)` (which is also what determines where the
    /// system's own grab/resize handle lands, right at the tabletop —
    /// SwiftUI exposes no way to draw or reposition that handle from inside
    /// this view's own body) and `GameRenderer.rootOffset`'s depth term
    /// (kept there as its own read of `frontClearance`/`volumeSize` rather
    /// than a second hardcoded literal — see that property's own doc for
    /// why depth specifically stays a fixed constant instead of a live
    /// window-bounds read).
    ///
    /// `width` is derived from `GameMetrics.tableWidth` (the table's actual
    /// X-extent) plus `sideClearance` on each side — this used to reuse
    /// `tableLength` instead (the table's *Z*-extent, 2.0 m vs. `tableWidth`'s
    /// 1.5 m), which left the handle/ornaments sitting ~30 cm off the
    /// table's real edge rather than the ~1 cm this now targets. `depth`
    /// uses `tableLength` (correctly — the table's Z-extent) plus
    /// `frontClearance` at the front (also tightened, to 15 cm, for the
    /// same handle/ornament-alignment reason as `sideClearance` — see that
    /// property's own doc for why it's 15 cm rather than matching
    /// `sideClearance`'s 1 cm) and `backClearance` at the back (left alone —
    /// see its own doc).
    public static var volumeSize: Size3D {
        Size3D(
            width: Double(GameMetrics.tableWidth) + sideClearance * 2,
            height: volumeHeight,
            depth: frontClearance + Double(GameMetrics.tableLength) + backClearance
        )
    }
}

#endif
