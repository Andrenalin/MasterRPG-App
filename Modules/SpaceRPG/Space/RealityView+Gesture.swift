// @copyright André Trettin

#if !os(tvOS)

import Foundation
import RealityKit
import SwiftUI

// MARK: - RealityView Extensions
public extension RealityView {

    /// Apply this to a `RealityView` to pass gestures on to the component code.
    ///
    /// - Parameter onDragEnded: An additional action run when the drag ends,
    ///   chained onto the *same* `DragGesture` instance `useGestureComponent`
    ///   already drives — not a second, competing `.targetedToAnyEntity()`
    ///   recognizer. Attaching a separate `DragGesture().targetedToAnyEntity()`
    ///   alongside this one (even via `.simultaneousGesture`) breaks dragging:
    ///   multiple entity-targeted drag recognizers on the same RealityView
    ///   content fight over which one resolves the target/owns the gesture.
    func installGestures(_ canDrag: Bool = true, onDragEnded: ((EntityTargetValue<DragGesture.Value>) -> Void)? = nil) -> some View {
#if os(visionOS)
        simultaneousGesture(dragGesture(onDragEnded: onDragEnded))
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
#else
        simultaneousGesture(dragGesture(canDrag: canDrag, onDragEnded: onDragEnded))
            .simultaneousGesture(magnifyGesture)
#endif
    }

    /// Builds a drag gesture. See `installGestures` for why `onDragEnded`
    /// chains onto this gesture instead of being a separate one.
    func dragGesture(canDrag: Bool = true, onDragEnded: ((EntityTargetValue<DragGesture.Value>) -> Void)? = nil) -> some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .useGestureComponent(canDrag)
            .onEnded { value in onDragEnded?(value) }
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
