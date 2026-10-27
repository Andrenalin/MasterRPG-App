// @copyright André Trettin

import Foundation
import Synchronization

/// Lets background App Intents wait until the Core Data stack and the root models exist.
///
/// Intents declared with `.background` can run when the app was launched without a scene, i.e.
/// before the view-driven database setup ran. Without a gate they insert into a root model that
/// has no `dataControllable`, "save" nothing and report success, and entity queries resolve to
/// empty lists. See CODE_AUDIT_16 §5.3.
@MainActor
public enum DatabaseReadiness {
    /// Longest an intent waits before continuing anyway (e.g. an iCloud account alert is pending).
    public static let timeout: Duration = .seconds(20)

    /// Ready once the root models exist *and* every module's initial load (the
    /// `SyncDataControllable.start()` full fetch) has finished. Marking ready right after the
    /// root models were set up let a cold-launch intent see (and cache) empty item lists.
    /// See CODE_AUDIT_18 §3.2.
    public static var isReady: Bool {
        rootModelsReady && InitialLoadTracker.shared.isIdle
    }

    /// Whether the root models (and with them the data controllers) exist, so a save reaches the store.
    public static var canSave: Bool { rootModelsReady }

    private static var rootModelsReady = false
    private static var starter: (@MainActor () -> Void)?
    private static var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Registers the closure that starts database setup when no scene did.
    public static func configure(start: @escaping @MainActor () -> Void) {
        starter = start
    }

    public static func markReady() {
        rootModelsReady = true
        resumeIfReady()
    }

    /// Called when a module's initial load finished.
    static func resumeIfReady() {
        guard isReady else { return }
        resumeAll()
    }

    /// Returns once the database and root models are ready, after `timeout`, or when the
    /// calling task is cancelled (a cancelled intent must not stay parked for the full
    /// timeout, CODE_AUDIT_18 §3.12). The result says whether the database can take writes now (the root
    /// models exist; a module's initial load may still be running, which only means item lists are
    /// incomplete). Read-only callers may continue either way, but a caller that writes must stop
    /// when it is `false`, because a save without a database reports success and stores nothing.
    /// See CODE_AUDIT §5.1.
    @discardableResult
    public static func wait() async -> Bool {
        guard !isReady else { return true }
        starter?()
        guard !isReady else { return true }
        // No registered starter (tests, previews, or a starter that has not been
        // configured yet) still waits for `markReady`/the timeout rather than
        // returning immediately, so a starter racing this call cannot be skipped.
        // See CODE_AUDIT_17 §3.3.
        let id = UUID()
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            waiters.removeValue(forKey: id)?.resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor in
                waiters.removeValue(forKey: id)?.resume()
            }
        }
        timeoutTask.cancel()
        return canSave
    }

    private static func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.values.forEach { $0.resume() }
    }
}

/// Counts the module initial loads that are still running. Nonisolated and lock-based so
/// `SyncDataControllable.start()` can register a load synchronously, before the root setup
/// that called it marks the root models ready. See CODE_AUDIT_18 §3.2.
final class InitialLoadTracker: Sendable {
    static let shared = InitialLoadTracker()

    private let running = Mutex<Set<UUID>>([])

    var isIdle: Bool {
        running.withLock { $0.isEmpty }
    }

    func begin() -> UUID {
        let token = UUID()
        running.withLock { _ = $0.insert(token) }
        return token
    }

    func end(_ token: UUID) async {
        let isIdle = running.withLock { running -> Bool in
            running.remove(token)
            return running.isEmpty
        }
        guard isIdle else { return }
        await DatabaseReadiness.resumeIfReady()
    }
}
