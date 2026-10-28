// @copyright André Trettin

import Foundation

/// Whether a RealityKit `RealityView` was made in this process.
///
/// On a device that can scan, `ObjectCaptureSession` gets no camera feed anymore after any
/// `RealityView` existed earlier in the process, even a removed or empty one, and nothing in the
/// app can undo that. Every `RealityView` on iOS notes itself here (the 3D viewer, the 3D game
/// table), so the scanner asks for a relaunch instead of hanging on "Move iPhone to start".
/// See CODE_AUDIT_Since_3.0.1 §5.15.
@MainActor
public enum RealityViewPresence {
    public private(set) static var wasCreated = false

    /// Call from the `make` closure of a `RealityView`.
    public static func noteCreated() {
        wasCreated = true
    }
}
