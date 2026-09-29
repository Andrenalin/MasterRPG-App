// @copyright André Trettin

import CoreData
import Foundation
import Synchronization

/// Tracks, per shared `NSManagedObjectContext`, the pending-operation queues of every
/// module's `CoreDataController`.
///
/// All modules flush into one context and any of them can save or roll it back. A save
/// commits every module's flushed edits; a rollback discards them. The ledger tells each
/// queue which of the two happened, so flushed edits are forgotten only once they are on
/// disk and are re-queued (not lost) when some module's failed save rolls the context back.
/// See CODE_AUDIT_18 §5.3.
final class ContextFlushLedger: Sendable {
    static let shared = ContextFlushLedger()

    private struct WeakModel: Sendable {
        weak var model: CoreDataModel?
    }

    private struct UncheckedObserver: @unchecked Sendable {
        let value: NSObjectProtocol
        /// Detects a new context allocated at a dead one's address after a store swap.
        weak var context: NSManagedObjectContext?
    }

    private let entries = Mutex<[ObjectIdentifier: [WeakModel]]>([:])
    private let observers = Mutex<[ObjectIdentifier: UncheckedObserver]>([:])

    func register(_ model: CoreDataModel, for context: NSManagedObjectContext) {
        let key = ObjectIdentifier(context)
        // Keyed by address: an entry left by a released context at the same address belongs
        // to a torn-down store and must not be reused. See CODE_AUDIT_19 §3.7.
        let isReusedAddress = observers.withLock { observers in
            guard let existing = observers[key], existing.context !== context else { return false }
            NotificationCenter.default.removeObserver(existing.value)
            observers[key] = nil
            return true
        }
        entries.withLock { entries in
            var models = isReusedAddress ? [] : entries[key, default: []].filter { $0.model != nil }
            models.append(WeakModel(model: model))
            entries[key] = models
        }
        observers.withLock { observers in
            guard observers[key] == nil else { return }
            // Every save of the shared context commits every module's flushed edits,
            // including saves made by the link/tag/statistics controllers.
            let token = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: context,
                queue: nil
            ) { [weak self] _ in
                self?.didCommit(key)
            }
            observers[key] = UncheckedObserver(value: token, context: context)
        }
    }

    /// Drops the context's queues and its save observer. Call when the store is torn down
    /// (`CoreDataInitModel.stop()`). See CODE_AUDIT_19 §3.7.
    func unregister(_ context: NSManagedObjectContext) {
        let key = ObjectIdentifier(context)
        entries.withLock { _ = $0.removeValue(forKey: key) }
        let observer = observers.withLock { $0.removeValue(forKey: key) }
        if let observer {
            NotificationCenter.default.removeObserver(observer.value)
        }
    }

    /// Call on the context's queue right after `rollback()`.
    func didRollBack(_ context: NSManagedObjectContext) {
        for model in models(for: ObjectIdentifier(context)) {
            model.restoreInFlight()
        }
    }

    private func didCommit(_ key: ObjectIdentifier) {
        for model in models(for: key) {
            model.commitInFlight()
        }
    }

    private func models(for key: ObjectIdentifier) -> [CoreDataModel] {
        entries.withLock { $0[key, default: []].compactMap(\.model) }
    }
}

extension NSManagedObjectContext {
    /// Rolls the context back and re-queues every module's flushed-but-unsaved edits that the
    /// rollback discarded. Use instead of a bare `rollback()` on the shared app context. Must
    /// run on the context's queue. See CODE_AUDIT_18 §5.3.
    public func rollbackRestoringFlushedOperations() {
        rollback()
        ContextFlushLedger.shared.didRollBack(self)
    }
}
