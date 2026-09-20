// @copyright André Trettin

import Foundation

/// Tracks whether an in-flight drag gesture's `.onChanged` stream has gone long enough without a
/// follow-up call that its originating gesture almost certainly never delivered `.onEnded` — a
/// system interruption, window backgrounding mid-drag, or similar. A later `.onChanged` that
/// arrives after the gap re-arms from a fresh baseline instead of leaving every future gesture
/// wedged against a stale one. Uses a monotonic clock, so wall-clock changes can't fake staleness.
struct StaleGestureTracker {
    private var lastUpdate: ContinuousClock.Instant?

    /// Call from a gesture's `.onChanged` handler.
    mutating func recordUpdate() {
        lastUpdate = .now
    }

    /// Call from a gesture's `.onEnded` handler (or wherever the in-flight state it backs gets cleared).
    mutating func reset() {
        lastUpdate = nil
    }

    func isStale(after timeout: Duration) -> Bool {
        guard let lastUpdate else { return false }
        return .now - lastUpdate > timeout
    }
}

/// Cancels the task currently held in `taskSlot` and replaces it with a freshly spawned one
/// wrapping `action` — the single-choke-point cancel-then-replace pattern `GameTableModel` uses for
/// its fog and map tasks, applied here to a room toggle/focus tap so a rapid second tap cancels the
/// first instead of both racing the fog recomposite.
@MainActor
func replaceTask(in taskSlot: inout Task<Void, Never>?, with action: @escaping @MainActor @Sendable () async -> Void) {
    taskSlot?.cancel()
    taskSlot = Task { await action() }
}

/// Cancel-then-replace dispatch for a room toggle/focus tap, held via a single
/// `@State private var roomActionCoordinator = RoomActionCoordinator()` and shared by composition
/// between the visionOS and iOS/macOS `GameTableView`s. A reference type so calling `perform(_:)`
/// mutates its own state directly, with no `mutating`/`inout` friction at the View's call sites.
@MainActor
final class RoomActionCoordinator {
    static let staleGestureTimeout: Duration = .seconds(3)

    private var task: Task<Void, Never>?

    func perform(_ action: @escaping @MainActor @Sendable () async -> Void) {
        replaceTask(in: &task, with: action)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
