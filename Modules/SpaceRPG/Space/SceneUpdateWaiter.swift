// @copyright André Trettin

#if os(visionOS)
import Combine
import RealityKit

/// Waits for the next `SceneEvents.Update` of an entity's scene: a real engine tick, instead
/// of guessing how long a pose takes to settle with `Task.sleep`. Cancellation-safe: a
/// cancelled wait resumes and tears down its subscription. See CODE_AUDIT_19 §3.16.
@MainActor
final class SceneUpdateWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private var subscription: (any Cancellable)?

    /// Returns `false` when the entity is not in a scene (no tick will ever come) or the
    /// calling task was cancelled.
    static func nextUpdate(of entity: Entity) async -> Bool {
        guard let scene = entity.scene else { return false }
        let waiter = SceneUpdateWaiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.continuation = continuation
                waiter.subscription = scene.subscribe(to: SceneEvents.Update.self) { [weak waiter] _ in
                    waiter?.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in
                waiter.resume()
            }
        }
        return !Task.isCancelled
    }

    private func resume() {
        subscription?.cancel()
        subscription = nil
        continuation?.resume()
        continuation = nil
    }
}
#endif
