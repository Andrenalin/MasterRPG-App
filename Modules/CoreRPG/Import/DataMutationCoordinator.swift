// @copyright André Trettin

import Foundation
import Observation

/// Process-wide exclusion for operations that mutate the shared RPG controller graph.
///
/// The coordinator lives in CoreRPG so imports launched by lower-level modules participate in
/// the same exclusion as application-level imports and database repair operations.
///
/// Bulk writers (file import, Foundry commit, Validate/Repair, the example-data install) take
/// the lock with `begin()` and are refused while another one holds it. CloudKit sync batches and
/// game network imports do not take it: they `waitUntilIdle()` and then apply, so they never
/// interleave with a bulk writer and nothing they carry is dropped. Direct UI edits are not
/// coordinated. See CODE_AUDIT_Folder §3.5.
@MainActor @Observable
public final class DataMutationCoordinator: Sendable {
    @MainActor public static let shared = DataMutationCoordinator()

    public private(set) var isActive = false

    @ObservationIgnored private var activeToken: UUID?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Returns an ownership token, or `nil` when another mutation is already active.
    public func begin() -> UUID? {
        guard activeToken == nil else { return nil }

        let token = UUID()
        activeToken = token
        isActive = true
        return token
    }

    /// Releases the coordinator only when `token` belongs to the active operation.
    public func end(_ token: UUID) {
        guard activeToken == token else { return }

        activeToken = nil
        isActive = false
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Returns once no bulk mutation holds the lock. Not cancellable: a waiter that was
    /// cancelled still resumes when the active mutation ends, and its caller then checks
    /// whether the work is still wanted.
    public func waitUntilIdle() async {
        while activeToken != nil {
            await withCheckedContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }
    }
}
