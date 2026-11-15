// @copyright André Trettin

import Foundation

/// When the per-frame sync of `ImagePresentationView` runs. Pure and platform independent, so the
/// rule is tested on iOS: the sync stops when the view disappears and starts again when it is
/// visible without a new `RealityView.make`. See CODE_AUDIT_26 §5.39.
struct FrameSyncLifecycle: Equatable {
    private(set) var isRunning = false
    private(set) var isVisible = false

    /// The sync is stopped while the view is on screen, so it must be started again.
    var needsRestart: Bool { isVisible && !isRunning }

    mutating func appeared() { isVisible = true }

    mutating func disappeared() {
        isVisible = false
        isRunning = false
    }

    mutating func started() { isRunning = true }

    mutating func stopped() { isRunning = false }
}
