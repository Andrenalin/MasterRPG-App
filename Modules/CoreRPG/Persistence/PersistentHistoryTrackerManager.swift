// @copyright André Trettin

import Combine
@preconcurrency import CoreData
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
    public static func scheduleRecurringCleanup(_ cleanup: @MainActor @escaping () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: initialCleanupDelay)
            await cleanup()
            while !Task.isCancelled {
                try? await Task.sleep(for: recurringCleanupInterval)
                await cleanup()
            }
        }
    }

    public func clean() {
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
        let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

        let allActors = appActors
        let cleanupTimestamp = timestamp
        container.performBackgroundTask { context in
            do {
                try context.execute(deleteHistoryRequest)
                Logger.persistentHistory.info("Cleaned history before \(cleanupTimestamp, privacy: .public)")

                Task {
                    await PersistentHistoryTimestampUpdater.shared.advanceTimestamps(for: allActors, to: cleanupTimestamp)
                    Logger.persistentHistory.info("Updated timestamps for \(allActors.count) actors to \(cleanupTimestamp, privacy: .public)")
                }
            } catch {
                Logger.persistentHistory.error("Clean History error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private actor PersistentHistoryTimestampUpdater {
    static let shared = PersistentHistoryTimestampUpdater()

    // Falls back to `.standard` when the App Group entitlement/provisioning profile doesn't
    // grant access, rather than crashing — see CODE_AUDIT §5.1. Timestamps then stay
    // per-device instead of shared across the app and its extensions, which only degrades
    // history-cleanup efficiency, not correctness.
    private let userDefault = UserDefaults(suiteName: UserDefaults.appGroupString) ?? .standard

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
            userDefaults: UserDefaults(suiteName: UserDefaults.appGroupString) ?? .standard
        )
        self.processor = processor

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator)
            .sink { _ in
                Task {
                    await processor.schedule()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
        let processor = processor
        Task {
            await processor.cancel()
        }
    }

    private let processor: PersistentHistoryProcessor
    private var cancellables: Set<AnyCancellable> = []
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

    func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
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
        let fromDate = loadDate()
        let currentActor = currentActor
        let userDefaults = userDefaults
        let viewContext = viewBackupContext
        let backgroundContext = backgroundContext

        do {
            let transactions = try await backgroundContext.perform {
                try Self.fetcher(date: fromDate, currentActor: currentActor, backgroundContext: backgroundContext)
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
        case historyTransactionConvertionFailed
    }

    private static func fetcher(
        date fromDate: Date,
        currentActor: AppPersistentActor,
        backgroundContext: NSManagedObjectContext
    ) throws -> [NSPersistentHistoryTransaction] {
        let historyFetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: fromDate)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates: [NSPredicate] = []

            AppPersistentActor.allCases.forEach { appActor in
                if appActor == currentActor {
                    // For own transactions, only process batchContext (which generates history)
                    // Regular background_context changes don't need to be merged back to itself
                    let predicate = NSPredicate(format: "%K = %@ AND %K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue, #keyPath(NSPersistentHistoryTransaction.contextName), "batchContext")
                    predicates.append(predicate)
                } else {
                    // For other actors, process all their transactions (they need to be merged into this actor's contexts)
                    let predicate = NSPredicate(format: "%K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue)
                    predicates.append(predicate)
                }
            }

            let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            historyFetchRequest.fetchRequest = fetchRequest
        }

        guard let historyResult = try backgroundContext.execute(historyFetchRequest) as? NSPersistentHistoryResult, let history = historyResult.result as? [NSPersistentHistoryTransaction] else { throw Error.historyTransactionConvertionFailed }
        return history
    }
    
    private func loadDate() -> Date {
        userDefaults.lastHistoryTransactionTimestamp(for: currentActor) ?? Date.distantPast
    }

    private static func merge(
        transactions: [NSPersistentHistoryTransaction],
        into viewBackupContext: NSManagedObjectContext?,
        userDefaults: UserDefaults,
        currentActor: AppPersistentActor
    ) async {
        guard let viewContext = viewBackupContext else { return }
        await viewContext.perform {
            transactions.forEach { transaction in
                let userInfo = transaction.objectIDNotification().userInfo ?? [:]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [viewContext])
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
