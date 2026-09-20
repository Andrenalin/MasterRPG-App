// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import Combine
import DiceRPG
import TabletopKit
#endif

#if os(visionOS)
extension GameTableModel {
    // MARK: - Rendering Readiness

    /// Awaits one `SceneEvents.Update` from `renderer.root.scene` — proof that a frame has
    /// actually rendered, needed before SharePlay coordination can safely run (see the call
    /// site in `GameTableView` for why a fixed number of `Task` turns wasn't reliably enough
    /// of a wait). A no-op if the scene isn't attached yet, rather than hanging forever.
    ///
    /// Cancellation-safe: if the awaiting `Task` is cancelled (e.g. the view is dismissed
    /// before any frame renders), the pending continuation is resumed and the RealityKit
    /// subscription torn down here instead of leaking for the process lifetime.
    func waitForFirstRenderedFrame() async {
        guard let scene = renderer.root.scene else { return }
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
