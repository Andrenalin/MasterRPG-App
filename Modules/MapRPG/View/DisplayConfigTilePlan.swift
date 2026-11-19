// @copyright André Trettin

import CoreGraphics
import Foundation

/// Decides which part of the map photo the cover-tile preview of `DisplayConfigEditor` shows.
/// See CODE_AUDIT_TestGaps §8.5.
enum DisplayConfigTilePlan {
    /// The photo area of the tile, or `nil` when no tile is configured. A tile is the four corner
    /// points the game master picked; any other number of points is not a tile.
    static func tileRect(coordinates: [CGPoint]) -> CGRect? {
        guard coordinates.count == 4 else { return nil }
        return coordinates.bounds
    }
}
