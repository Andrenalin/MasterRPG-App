// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable
final class ImageViewerModel {
    init(offset: CGPoint = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.lastOffset = offset
        self.scale = scale
        self.lastScale = scale
        normScale = scale
    }

    var offset: CGPoint
    var lastOffset: CGPoint
    var scale: CGFloat
    var lastScale: CGFloat

    var normScale: CGFloat
}
