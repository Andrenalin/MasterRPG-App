// @copyright André Trettin

import Foundation

/// A started security-scoped resource access that is only stopped again when it was actually
/// started. `startAccessingSecurityScopedResource()` returns `false` for urls that need no scope
/// (an app-container file); stopping one anyway is an unbalanced call that can end an outer
/// scope's access. Sites that wrote `_ = url.start…` followed by an unconditional
/// `defer { url.stop… }` all had that problem. See CODE_AUDIT_15 §9.17.
public struct SecurityScopedAccess: Sendable {
    fileprivate let url: URL
    fileprivate let didStart: Bool

    /// Ends the access if this value started it.
    public func stop() {
        guard didStart else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

public extension URL {
    /// Starts security-scoped access; call `stop()` on the result (typically in a `defer`).
    func startSecurityScopedAccess() -> SecurityScopedAccess {
        SecurityScopedAccess(url: self, didStart: startAccessingSecurityScopedResource())
    }
}

public extension URL {
    /// Runs synchronous `work` off the caller's executor with security-scoped access to this
    /// URL, balancing start/stop and honouring cancellation of the calling task. Replaces the
    /// hand-rolled "`Task.detached` + start/stop scope + cancellation handler" wrapper that
    /// was copied into the import readers. See CODE_AUDIT_18 §4.4 and §9.10.
    @concurrent
    func withSecurityScopedAccess<T: Sendable>(_ work: @Sendable (URL) throws -> T) async throws -> T {
        let access = startSecurityScopedAccess()
        defer { access.stop() }
        try Task.checkCancellation()
        let result = try work(self)
        try Task.checkCancellation()
        return result
    }
}

public extension URL {
    /// Async variant for work that also awaits (e.g. actor-backed caches). The closure is
    /// nonisolated, so it runs on this `@concurrent` function's executor, not the caller's.
    @concurrent
    func withSecurityScopedAccess<T: Sendable>(_ work: @Sendable (URL) async throws -> T) async throws -> T {
        let access = startSecurityScopedAccess()
        defer { access.stop() }
        try Task.checkCancellation()
        let result = try await work(self)
        try Task.checkCancellation()
        return result
    }
}

/// Runs `work` at `.medium` (Default QoS) instead of the caller's priority. ImageIO's decode
/// hands its work to Default-QoS threads and blocks until they finish, so a decode inherited
/// from a User-initiated caller (a view's `.task`) is reported as a priority inversion.
///
/// A child task does not help: a parent waiting on its child escalates the child to the
/// parent's priority, which put the decode back at User-initiated. `work` runs in a detached
/// task instead, and the caller waits for its result through a continuation, which escalates
/// nothing. The caller's cancellation is passed on to that task.
public func runAtDefaultPriority<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
    let task = Task.detached(priority: .medium) { await work() }
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            // Waits at `.medium` itself, so `task` is not escalated by its waiter either.
            Task.detached(priority: .medium) {
                continuation.resume(returning: await task.value)
            }
        }
    } onCancel: {
        task.cancel()
    }
}

/// Runs synchronous `work` off the caller's executor. Structured (unlike `Task.detached`), so
/// the calling task's cancellation reaches `work`'s own `Task.checkCancellation()` calls
/// without a separate cancellation handler. See CODE_AUDIT_18 §4.4.
@concurrent
public func runOffCallerExecutor<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
    try Task.checkCancellation()
    let result = try work()
    try Task.checkCancellation()
    return result
}
