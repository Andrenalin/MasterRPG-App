// @copyright André Trettin

import Foundation

/// Tracks whether an in-flight drag gesture's `.onChanged` stream has gone long enough without a
/// follow-up call that its originating gesture almost certainly never delivered `.onEnded` — a
/// system interruption, window backgrounding mid-drag, or similar. A later `.onChanged` that
/// arrives after the gap re-arms from a fresh baseline instead of leaving every future gesture
/// wedged against a stale one. Uses a monotonic clock, so wall-clock changes can't fake staleness.
struct StaleGestureTracker {
    /// How long a drag may go without an update before it counts as abandoned. Lived on
    /// `RoomActionCoordinator`, which never used it. See CODE_AUDIT_19 §9.25.
    static let defaultTimeout: Duration = .seconds(3)

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
