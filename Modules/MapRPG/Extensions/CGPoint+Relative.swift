// @copyright André Trettin

import CoreGraphics

extension CGPoint {
    func relative(to size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}
