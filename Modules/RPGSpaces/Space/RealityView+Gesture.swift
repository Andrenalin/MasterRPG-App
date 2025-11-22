// @copyright André Trettin

#if !os(tvOS)

import Foundation
import RealityKit
import SwiftUI

// MARK: - RealityView Extensions
public extension RealityView {

    /// Apply this to a `RealityView` to pass gestures on to the component code.
    func installGestures(_ canDrag: Bool = true) -> some View {
#if os(visionOS)
        simultaneousGesture(dragGesture())
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
#else
        simultaneousGesture(dragGesture(canDrag: canDrag))
            .simultaneousGesture(magnifyGesture)
#endif
    }

    /// Builds a drag gesture.
    func dragGesture(canDrag: Bool = true) -> some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .useGestureComponent(canDrag)
    }

    /// Builds a magnify gesture.
    var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .useGestureComponent()
    }

#if os(visionOS)
    /// Buildsa rotate gesture.
    var rotateGesture: some Gesture {
        RotateGesture3D()
            .targetedToAnyEntity()
            .useGestureComponent()
    }
#endif
}

#endif
