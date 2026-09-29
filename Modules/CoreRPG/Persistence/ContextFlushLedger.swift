// @copyright André Trettin

import CoreData
import Foundation
import os.log
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

    /// Call on the context's queue right after `rollback()`. Operations for `failingIds`, or
    /// ones retried too often, are discarded and reported instead of re-queued.
    /// See CODE_AUDIT_19 §5.3.
    func didRollBack(_ context: NSManagedObjectContext, failingIds: Set<UUID> = []) {
        var discarded: [UUID] = []
        for model in models(for: ObjectIdentifier(context)) {
            discarded += model.restoreInFlight(failingIds: failingIds).map(\.id)
        }
        guard !discarded.isEmpty else { return }
        Logger.coreDataController.error("Discarded \(discarded.count) edits after repeated save failures: \(discarded.map(\.uuidString).joined(separator: ", "), privacy: .public)")
        let count = discarded.count
        Task { @MainActor in
            PersistenceIssueCenter.shared.recordDiscardedEdits(count)
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
    ///
    /// Pass the save error: the items it names are quarantined instead of retried, so one
    /// invalid object can't make every later save fail. See CODE_AUDIT_19 §5.3.
    public func rollbackRestoringFlushedOperations(after error: (any Error)? = nil) {
        // Read before `rollback()`, while the failing objects are still registered.
        let failingIds = error.map(Self.failingItemIds(in:)) ?? []
        rollback()
        ContextFlushLedger.shared.didRollBack(self, failingIds: failingIds)
    }

    /// Ids of the items a failed save names: validation failures (single or
    /// `NSDetailedErrorsKey`) and merge conflicts. Objects without a `uuid` are skipped;
    /// the retry cap still bounds those. Must run on the context's queue.
    static func failingItemIds(in error: any Error) -> Set<UUID> {
        let nsError = error as NSError
        var errors = [nsError]
        errors += nsError.userInfo[NSDetailedErrorsKey] as? [NSError] ?? []
        var objects = errors.compactMap { $0.userInfo[NSValidationObjectErrorKey] as? NSManagedObject }
        let conflicts = nsError.userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict] ?? []
        objects += conflicts.map(\.sourceObject)
        return Set(objects.compactMap { ($0 as? any CoreDataId)?.uuid })
    }
}
