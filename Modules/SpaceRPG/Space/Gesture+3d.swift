// @copyright André Trettin

#if !os(tvOS)
import Foundation
import RealityKit
import SwiftUI

// MARK: - Rotate -

#if os(visionOS)
/// Gesture extension to support rotation gestures.
public extension Gesture where Value == EntityTargetValue<RotateGesture3D.Value> {
    
    /// Connects the gesture input to the `GestureComponent` code.
    func useGestureComponent() -> some Gesture {
        onChanged { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            
            gestureComponent.onChanged(value: value)
            
            value.entity.components.set(gestureComponent)
        }
        .onEnded { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            
            gestureComponent.onEnded(value: value)
            
            value.entity.components.set(gestureComponent)
        }
    }
}
#endif


// MARK: - Drag -

/// Gesture extension to support drag gestures.
public extension Gesture where Value == EntityTargetValue<DragGesture.Value> {
    
    /// Connects the gesture input to the `GestureComponent` code.
    ///
    /// Parameterized (`some Gesture<Value>`, not a bare `some Gesture`) so
    /// callers outside this extension — e.g. `dragGesture(onDragEnded:)` —
    /// can still chain their own `.onEnded` onto the result with a concretely
    /// typed closure. A bare `some Gesture` erases `Value` at this function's
    /// boundary, and SwiftUI's generic `.onEnded<T>(_: (Self.Value) -> Void)`
    /// can't unify an erased opaque `Value` with a caller-supplied concrete
    /// closure type.
    func useGestureComponent(_ canDrag: Bool = true) -> some Gesture<EntityTargetValue<DragGesture.Value>> {
        onChanged { value in
            guard canDrag else { return }
            guard var gestureComponent = value.entity.gestureComponent else { return }

            gestureComponent.onChanged(value: value)

            value.entity.components.set(gestureComponent)
        }
        .onEnded { value in
            guard canDrag else { return }
            guard var gestureComponent = value.entity.gestureComponent else { return }

            gestureComponent.onEnded(value: value)

            value.entity.components.set(gestureComponent)
        }
    }
}

// MARK: - Magnify (Scale) -

/// Gesture extension to support scale gestures.
public extension Gesture where Value == EntityTargetValue<MagnifyGesture.Value> {
    
    /// Connects the gesture input to the `GestureComponent` code.
    func useGestureComponent() -> some Gesture {
        onChanged { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            
            gestureComponent.onChanged(value: value)
            
            value.entity.components.set(gestureComponent)
        }
        .onEnded { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            
            gestureComponent.onEnded(value: value)
            
            value.entity.components.set(gestureComponent)
        }
    }
}

#endif
