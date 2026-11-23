// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import Combine
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import DiceRPG
import TabletopKit
#endif

#if os(visionOS)
extension GameTableModel {
    // MARK: - Rendering Readiness

    /// Awaits one `SceneEvents.Update` from `renderer.root.scene` — proof that a frame has
    /// actually rendered, needed before SharePlay coordination can safely run (see the call
    /// site in `GameTableView` for why a fixed number of `Task` turns wasn't reliably enough
    /// of a wait). It first waits (bounded) for the scene to be attached: the root has none until
    /// the RealityView's `make` ran, and returning then would let the caller join SharePlay
    /// before the mount. See CODE_AUDIT_28 §5.16.
    ///
    /// - Returns: `false` when the scene never came up or the wait was cancelled; the caller must
    ///   not start coordination then.
    ///
    /// Cancellation-safe: if the awaiting `Task` is cancelled (e.g. the view is dismissed
    /// before any frame renders), the pending continuation is resumed and the RealityKit
    /// subscription torn down here instead of leaking for the process lifetime.
    @discardableResult
    func waitForFirstRenderedFrame() async -> Bool {
        guard await SceneAttachmentWait.wait(isAttached: { renderer.root.scene != nil }),
              let scene = renderer.root.scene else {
            Logger.gameTable.error("Table scene not attached in time; SharePlay coordination is not started")
            return false
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // A second concurrent wait must not orphan the first one's continuation.
                resumePendingRenderWait()
                pendingRenderWaitContinuation = continuation
                pendingRenderWaitSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                    self?.resumePendingRenderWait()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumePendingRenderWait()
            }
        }
        return !Task.isCancelled
    }

    private func resumePendingRenderWait() {
        guard let continuation = pendingRenderWaitContinuation else { return }
        pendingRenderWaitSubscription?.cancel()
        pendingRenderWaitSubscription = nil
        pendingRenderWaitContinuation = nil
        continuation.resume()
    }
}
#endif

#endif
