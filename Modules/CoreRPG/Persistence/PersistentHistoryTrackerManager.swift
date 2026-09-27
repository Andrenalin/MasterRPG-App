// @copyright André Trettin

import Combine
import CoreData
import Foundation
import os.log

public enum AppPersistentActor: String, CaseIterable, Sendable {
    case mainApp
    case sharingExtension
    // extensions that can read / write to the app group core database
    case rpgWidget
}

public struct PersistentHistoryCleaner {
    @MainActor public init(container: NSPersistentContainer) {
        self.container = container
        userDefault = UserDefaults.appGroup
    }

    let container: NSPersistentContainer
    // `nil` when the App Group entitlement/provisioning profile doesn't grant access — see
    // CODE_AUDIT §5.1. `clean()` is a periodic maintenance task, so it degrades to a no-op
    // rather than crashing.
    let userDefault: UserDefaults?
    let appActors = AppPersistentActor.allCases

    /// Delay before the first cleanup run, so it doesn't compete with launch.
    static let initialCleanupDelay: Duration = .seconds(5)
    /// Cadence for every cleanup run after the first.
    static let recurringCleanupInterval: Duration = .seconds(24 * 60 * 60)

    /// Runs `cleanup` once after `initialCleanupDelay`, then every
    /// `recurringCleanupInterval` until the returned task is cancelled.
    /// Shared by both `CoreDataPersistenceController` and
    /// `CloudKitCoreDataPersistenceController` so the schedule can't drift
    /// between the two setup paths.
    public static func scheduleRecurringCleanup(_ cleanup: @MainActor @escaping () async -> Void) -> Task<Void, Never> {
        Task {
            // `try?` swallowed the cancellation, so a cancelled (replaced) task still ran a
            // cleanup immediately. See CODE_AUDIT_15 §3.9.
            do {
                try await Task.sleep(for: initialCleanupDelay)
                await cleanup()
                while !Task.isCancelled {
                    try await Task.sleep(for: recurringCleanupInterval)
                    await cleanup()
                }
            } catch {
                return
            }
        }
    }

    public func clean() async {
        guard let userDefault else {
            Logger.persistentHistory.error("Skipping history cleanup: App Group container is unavailable")
            return
        }
        guard let timestamp = userDefault.lastCommonTransactionTimestamp(in: appActors) else {
            return
        }

        // Delete history before the safe timestamp — no actor filter, so CloudKit
        // mirroring transactions (author = NSCloudKitMirroringDelegate) are also cleaned.
        // The timestamp is capped at 7 days ago (see lastCommonTransactionTimestamp),
        // which is what protects transactions the mirroring delegate has not exported yet.
        let allActors = appActors
        let cleanupTimestamp = timestamp
        // Async `performBackgroundTask` instead of the completion form with a nested,
        // unowned `Task` for the timestamp update. See CODE_AUDIT_18 §4.2.
        do {
            try await container.performBackgroundTask { context in
                // Built on the background queue: the request isn't `Sendable`.
                let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cleanupTimestamp)
                try context.execute(deleteHistoryRequest)
            }
            Logger.persistentHistory.info("Cleaned history before \(cleanupTimestamp, privacy: .public)")
            await PersistentHistoryTimestampUpdater.shared.advanceTimestamps(for: allActors, to: cleanupTimestamp)
            Logger.persistentHistory.info("Updated timestamps for \(allActors.count) actors to \(cleanupTimestamp, privacy: .public)")
        } catch {
            Logger.persistentHistory.error("Clean History error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private actor PersistentHistoryTimestampUpdater {
    static let shared = PersistentHistoryTimestampUpdater()

    // Falls back to `.standard` when the App Group entitlement/provisioning profile doesn't
    // grant access, rather than crashing — see CODE_AUDIT §5.1. Timestamps then stay
    // per-device instead of shared across the app and its extensions, which only degrades
    // history-cleanup efficiency, not correctness.
    private let userDefault = UserDefaults.appGroupDefaults ?? .standard

    func advanceTimestamps(for actors: [AppPersistentActor], to timestamp: Date) {
        for actor in actors {
            // Never rewind an actor's position — that would make it reprocess history
            // it has already merged. Only advance actors that lag behind the cleanup point.
            if let current = userDefault.lastHistoryTransactionTimestamp(for: actor), current >= timestamp { continue }
            userDefault.updateLastHistoryTransactionTimestamp(for: actor, to: timestamp)
        }
    }
}

final class PersistentHistoryTrackerManager {
    init(container: NSPersistentContainer, currentActor: AppPersistentActor, viewBackupContext: NSManagedObjectContext?) {
        // Falls back to `.standard` when the App Group entitlement/provisioning profile
        // doesn't grant access, rather than crashing — see CODE_AUDIT §5.1.
        let processor = PersistentHistoryProcessor(
            container: container,
            currentActor: currentActor,
            viewBackupContext: viewBackupContext,
            userDefaults: UserDefaults.appGroupDefaults ?? .standard
        )
        self.processor = processor

        // One ordered consumer instead of a `Task` per notification. See CODE_AUDIT_18 §4.2.
        let coordinator = container.persistentStoreCoordinator
        remoteChangeTask = Task {
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange, object: coordinator) {
                await processor.schedule()
            }
        }
    }

    deinit {
        remoteChangeTask?.cancel()
        let processor = processor
        Task {
            await processor.cancel()
        }
    }

    private let processor: PersistentHistoryProcessor
    private var remoteChangeTask: Task<Void, Never>?
}

private actor PersistentHistoryProcessor {
    init(
        container: NSPersistentContainer,
        currentActor: AppPersistentActor,
        viewBackupContext: NSManagedObjectContext?,
        userDefaults: UserDefaults
    ) {
        self.currentActor = currentActor
        self.viewBackupContext = viewBackupContext
        self.userDefaults = userDefaults
        self.backgroundContext = container.newBackgroundContext()
    }

    deinit {
        debounceTask?.cancel()
    }

    private let currentActor: AppPersistentActor
    private let viewBackupContext: NSManagedObjectContext?
    private let userDefaults: UserDefaults
    private let backgroundContext: NSManagedObjectContext
    private var debounceTask: Task<Void, Never>?
    /// A pass already past its debounce sleep ignores the next `schedule()`'s cancellation,
    /// and actor reentrancy at `perform`/merge let a second pass start from the same
    /// `loadDate()` and merge the same transactions twice. Passes are serialized instead; a
    /// request that arrives mid-pass runs one more pass afterwards. See CODE_AUDIT_18 §3.14.
    private var isProcessing = false
    private var needsAnotherPass = false

    /// Debounce before processing a burst of remote-change notifications into one history
    /// fetch/merge pass, rather than one per notification. See CODE_AUDIT §9.14.
    private static let remoteChangeDebounce: Duration = .seconds(1)

    func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.remoteChangeDebounce)
                await self?.process()
            } catch is CancellationError {
            } catch {
                Logger.persistentHistory.error("Persistent history debounce failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func process() async {
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        repeat {
            needsAnotherPass = false
            await processPass()
        } while needsAnotherPass
        isProcessing = false
    }

    private func processPass() async {
        let fromDate = loadDate()
        let currentActor = currentActor
        let userDefaults = userDefaults
        let viewContext = viewBackupContext
        let backgroundContext = backgroundContext

        do {
            // Converted to Sendable object-ID snapshots on the background queue: the
            // `NSPersistentHistoryTransaction` objects themselves must not cross into the view
            // context's queue. See CODE_AUDIT_18 §3.18.
            let transactions = try await backgroundContext.perform {
                try Self.fetcher(date: fromDate, currentActor: currentActor, backgroundContext: backgroundContext)
                    .map(HistoryChanges.init)
            }
            if transactions.isEmpty {
                // Update timestamp to now even when empty, so we don't keep checking from distantPast
                if fromDate == Date.distantPast {
                    userDefaults.updateLastHistoryTransactionTimestamp(for: currentActor, to: Date())
                    Logger.persistentHistory.info("Initialized history timestamp for \(currentActor.rawValue)")
                }
                // Don't log when empty - reduces noise
            } else {
                await Self.merge(transactions: transactions, into: viewContext, userDefaults: userDefaults, currentActor: currentActor)
                Logger.persistentHistory.info("Processed \(transactions.count, privacy: .public) transactions")
            }
        } catch {
            Logger.persistentHistory.error("Failed to fetch history: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    enum Error: String, Swift.Error {
        case historyTransactionConversionFailed
    }

    private static func fetcher(
        date fromDate: Date,
        currentActor: AppPersistentActor,
        backgroundContext: NSManagedObjectContext
    ) throws -> [NSPersistentHistoryTransaction] {
        let historyFetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: fromDate)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            // Only OTHER actors' transactions ever need to be merged back into this actor's
            // contexts — this actor's own regular-context changes are already reflected in
            // its own contexts and never need reprocessing, so the current actor is simply
            // excluded rather than special-cased. (A dedicated "batchContext" used to exist
            // for capturing this actor's own history for that purpose, but nothing ever wrote
            // through it — removed along with the predicate that referenced it. See
            // CODE_AUDIT §9.1.)
            let predicates = AppPersistentActor.allCases
                .filter { $0 != currentActor }
                .map { appActor in
                    NSPredicate(format: "%K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue)
                }

            let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            historyFetchRequest.fetchRequest = fetchRequest
        }

        guard let historyResult = try backgroundContext.execute(historyFetchRequest) as? NSPersistentHistoryResult, let history = historyResult.result as? [NSPersistentHistoryTransaction] else { throw Error.historyTransactionConversionFailed }
        return history
    }
    
    private func loadDate() -> Date {
        userDefaults.lastHistoryTransactionTimestamp(for: currentActor) ?? Date.distantPast
    }

    /// The object IDs a history transaction changed, extracted on the fetching queue.
    private struct HistoryChanges: Sendable {
        let inserted: Set<NSManagedObjectID>
        let updated: Set<NSManagedObjectID>
        let deleted: Set<NSManagedObjectID>
        let timestamp: Date

        init(_ transaction: NSPersistentHistoryTransaction) {
            let userInfo = transaction.objectIDNotification().userInfo ?? [:]
            inserted = userInfo[NSInsertedObjectIDsKey] as? Set<NSManagedObjectID> ?? []
            updated = userInfo[NSUpdatedObjectIDsKey] as? Set<NSManagedObjectID> ?? []
            deleted = userInfo[NSDeletedObjectIDsKey] as? Set<NSManagedObjectID> ?? []
            timestamp = transaction.timestamp
        }

        var remoteSaveUserInfo: [AnyHashable: Any] {
            [NSInsertedObjectIDsKey: inserted, NSUpdatedObjectIDsKey: updated, NSDeletedObjectIDsKey: deleted]
        }
    }

    private static func merge(
        transactions: [HistoryChanges],
        into viewBackupContext: NSManagedObjectContext?,
        userDefaults: UserDefaults,
        currentActor: AppPersistentActor
    ) async {
        guard let viewContext = viewBackupContext else { return }
        await viewContext.perform {
            transactions.forEach { transaction in
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: transaction.remoteSaveUserInfo, into: [viewContext])
            }
        }

        guard let lastTimestamp = transactions.last?.timestamp else { return }
        userDefaults.updateLastHistoryTransactionTimestamp(for: currentActor, to: lastTimestamp)
    }
}

fileprivate extension UserDefaults {
    func lastCommonTransactionTimestamp(in appActors: [AppPersistentActor]) -> Date? {
        let sevenDaysAgo = Date().addingTimeInterval(-7*24*60*60)
        // Only delete history that every app actor has consumed AND that is at least
        // 7 days old. The CloudKit mirroring delegate is not tracked in appActors, so
        // the 7-day floor is the only protection for its unconsumed transactions —
        // deleting those invalidates its history token and forces a full re-mirror.
        let timestamp = appActors
            .compactMap { lastHistoryTransactionTimestamp(for: $0) }
            .min() ?? sevenDaysAgo
        return min(timestamp, sevenDaysAgo)
    }

    func lastHistoryTransactionTimestamp(for appActor: AppPersistentActor) -> Date? {
        let key = "PersistentHistoryTracker.lastToken.\(appActor.rawValue)"
        return object(forKey: key) as? Date
    }

    func updateLastHistoryTransactionTimestamp(for appActor: AppPersistentActor, to newDate: Date?) {
        let key = "PersistentHistoryTracker.lastToken.\(appActor.rawValue)"
        set(newDate, forKey: key)
    }
}
