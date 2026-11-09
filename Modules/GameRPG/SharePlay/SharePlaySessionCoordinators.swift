// @copyright André Trettin

import CoreRPG
import Foundation
import GroupActivities
import os.log

/// Revalidates a session-scoped loop on both sides of delegate suspension and
/// lets teardown await callbacks that were already admitted before reset.
/// Main-actor isolation makes admission plus active-count registration atomic
/// with respect to lifecycle reset.
@MainActor
final class SharePlaySessionCallbackCoordinator {
    private var activeCounts: [UUID: Int] = [:]
    private struct IdleWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        let timeoutTask: Task<Void, Never>
    }

    /// Longest a session replacement waits for callbacks of the previous session.
    static let defaultIdleTimeout: Duration = .seconds(10)

    private var idleWaiters: [UUID: [IdleWaiter]] = [:]

    func perform(
        sessionId: UUID,
        shouldContinue: @MainActor () -> Bool,
        operation: @MainActor () async -> Void
    ) async -> Bool {
        guard !Task.isCancelled, shouldContinue() else { return false }
        activeCounts[sessionId, default: 0] += 1
        defer { finishCallback(sessionId: sessionId) }

        await operation()
        return !Task.isCancelled && shouldContinue()
    }

    /// Waits until no admitted callback of the session is running, but at most `timeout`.
    /// A hung delegate callback must not wedge the reconnection to a replacement session
    /// (CODE_AUDIT_Game_Shareplay §3.10). Returns `false` when it gave up waiting; the
    /// callback keeps running and is still revalidated by `perform` when it returns.
    @discardableResult
    func waitUntilIdle(sessionId: UUID, timeout: Duration = defaultIdleTimeout) async -> Bool {
        guard activeCounts[sessionId, default: 0] > 0 else { return true }
        let waiterId = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.expireWaiter(id: waiterId, sessionId: sessionId)
            }
            idleWaiters[sessionId, default: []].append(
                IdleWaiter(id: waiterId, continuation: continuation, timeoutTask: timeoutTask)
            )
        }
    }

    private func expireWaiter(id: UUID, sessionId: UUID) {
        guard var waiters = idleWaiters[sessionId],
              let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        idleWaiters[sessionId] = waiters.isEmpty ? nil : waiters
        Logger.networking.error("SharePlay: gave up waiting for callbacks of the previous session")
        waiter.continuation.resume(returning: false)
    }

    private func finishCallback(sessionId: UUID) {
        let remainingCount = activeCounts[sessionId, default: 0] - 1
        guard remainingCount <= 0 else {
            activeCounts[sessionId] = remainingCount
            return
        }

        activeCounts.removeValue(forKey: sessionId)
        for waiter in idleWaiters.removeValue(forKey: sessionId) ?? [] {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(returning: true)
        }
    }
}

/// Keeps teardown callbacks alive independently of the session task being
/// cancelled, and gives a replacement configuration one operation to await.
/// The token prevents an older waiter from clearing a newer teardown.
@MainActor
final class SharePlaySessionTeardownCoordinator {
    struct Operation {
        fileprivate let token: UUID
        fileprivate let task: Task<Void, Never>
    }

    private struct PendingTeardown {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var pendingTeardown: PendingTeardown?

    func waitForPendingTeardown() async {
        while let pendingTeardown {
            await pendingTeardown.task.value
            clearPendingTeardown(matching: pendingTeardown.token)
        }
    }

    /// Registration is synchronous so a caller can publish the pending token
    /// before reset opens the main-actor reentrancy window.
    func start(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Operation {
        let precedingTask = pendingTeardown?.task
        let token = UUID()
        let task = Task { @MainActor in
            if let precedingTask {
                await precedingTask.value
            }
            await operation()
        }
        pendingTeardown = PendingTeardown(token: token, task: task)
        return Operation(token: token, task: task)
    }

    func waitForCompletion(of operation: Operation) async {
        await operation.task.value
        clearPendingTeardown(matching: operation.token)
    }

    private func clearPendingTeardown(matching token: UUID) {
        guard pendingTeardown?.token == token else { return }
        pendingTeardown = nil
    }
}

enum SharePlaySessionTeardownEvent: Equatable, Sendable {
    case lostParticipant(UUID)
    case lostConnection
}
