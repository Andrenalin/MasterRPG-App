// @copyright André Trettin

import CoreGraphics
import SwiftUI

/// Decides whether the game screen may reclaim the top safe area.
///
/// With the vertical bar disabled, iPhone Duo reserves a full-width top band only because
/// of the camera block in its top trailing corner. The game screen has no status bar, so
/// it can use that band as long as the top menu stays out of the corner.
enum GameTopOcclusion {
    /// The width to keep free at the trailing end of the top row, or zero when the top
    /// safe area has to stay (no corner block, or an inset the block doesn't account for).
    ///
    /// - Parameters:
    ///   - topInset: The top safe-area inset of the screen.
    ///   - screenWidth: The full screen width, including horizontal safe-area insets.
    ///   - occlusions: The screen's occlusion regions, in left-to-right screen coordinates.
    static func reclaimableCornerWidth(topInset: CGFloat, screenWidth: CGFloat, occlusions: [CGRect]) -> CGFloat {
        guard topInset > 0, screenWidth > 0 else { return 0 }
        let corner = occlusions.first { region in
            region.minY <= tolerance
                && region.maxX >= screenWidth - tolerance
                && region.width < screenWidth / 2
                && region.maxY >= topInset - tolerance
        }
        return corner?.width ?? 0
    }

    private static let tolerance: CGFloat = 0.5
}

extension EnvironmentValues {
    /// Width of the camera block in the top trailing corner that the game screen runs
    /// alongside after reclaiming the top safe area (iPhone Duo); zero everywhere else.
    @Entry var gameTopTrailingOcclusionWidth: CGFloat = 0
}
