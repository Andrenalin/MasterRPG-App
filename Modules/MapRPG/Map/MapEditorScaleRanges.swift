// @copyright André Trettin

import CoreGraphics
import Foundation

/// Slider ranges for the map editor's presentation-scale controls, colocated
/// so a future UX tuning pass has one place to look. Previously scattered as
/// unnamed literals across PinScaleView/MaxSizeScaleView/HexMapScaleView with
/// no visible relationship between them. See CODE_AUDIT §9.14.
enum MapEditorScaleRanges {
    static let pinScale: ClosedRange<CGFloat> = 0.5 ... 3.5
    static let maxSizeRatio: ClosedRange<Double> = 0.1 ... 1.0
    static let hexScale: ClosedRange<Double> = 20 ... 200
}
