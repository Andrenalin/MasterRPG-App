// @copyright André Trettin

import Foundation

// Split out of StaleGestureTracker.swift, which it had nothing to do with. See CODE_AUDIT_19 §9.25.

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
    private var task: Task<Void, Never>?

    func perform(_ action: @escaping @MainActor @Sendable () async -> Void) {
        replaceTask(in: &task, with: action)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
