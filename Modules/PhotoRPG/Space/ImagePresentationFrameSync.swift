// @copyright André Trettin

#if os(visionOS)

import RealityKit
import SwiftUI

/// Owns the per-frame sync of `ImagePresentationView`: the `SceneEvents.Update` subscription, the
/// coalescing stream and the consumer task. Starting always stops the previous run first, so a
/// second `RealityView.make` never leaves an orphaned task behind.
///
/// `SceneEvents.Update` is not MainActor-isolated, so each tick hops through a
/// `.bufferingNewest(1)` stream to one long-lived consumer instead of spawning a `Task` per
/// engine tick (~90 Hz).
@MainActor @Observable
final class ImagePresentationFrameSync {
    /// Observed: a change makes SwiftUI call the `RealityView` update closure, which restarts a
    /// stopped sync. The running state itself is not observed (it changes inside view updates).
    private(set) var isVisible = false

    @ObservationIgnored private var lifecycle = FrameSyncLifecycle()
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var continuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var task: Task<Void, Never>?

    var needsRestart: Bool { lifecycle.needsRestart }

    func appeared() {
        lifecycle.appeared()
        isVisible = true
    }

    func disappeared() {
        stop()
        lifecycle.disappeared()
        isVisible = false
    }

    func start(content: inout RealityViewContent, onFrame: @escaping @MainActor () -> Void) {
        stop()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        task = Task { @MainActor in
            for await _ in stream {
                onFrame()
            }
        }
        subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
            continuation.yield()
        }
        lifecycle.started()
    }

    /// The RealityKit subscription keeps firing (and holding the content) until it is cancelled.
    /// See CODE_AUDIT_18 §3.19.
    func stop() {
        subscription?.cancel()
        subscription = nil
        continuation?.finish()
        continuation = nil
        task?.cancel()
        task = nil
        lifecycle.stopped()
    }
}

#endif
