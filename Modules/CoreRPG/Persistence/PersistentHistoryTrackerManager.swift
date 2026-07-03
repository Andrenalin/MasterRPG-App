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

public struct PersistentHistoryCleaner: @unchecked Sendable {
    @MainActor public init(container: NSPersistentContainer) {
        self.container = container
        userDefault = UserDefaults.appGroup
    }

    let container: NSPersistentContainer
    let userDefault: UserDefaults
    let appActors = AppPersistentActor.allCases

    public func clean() {
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

                // Coordinate timestamp updates on MainActor
                Task { @MainActor in
                    allActors.forEach { actor in
                        self.updateTimeStamp(actor: actor, to: cleanupTimestamp)
                    }
                    Logger.persistentHistory.info("Updated timestamps for \(allActors.count) actors to \(cleanupTimestamp, privacy: .public)")
                }
            } catch {
                Logger.persistentHistory.error("Clean History error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor func updateTimeStamp(actor: AppPersistentActor, to timestamp: Date) {
        // Never rewind an actor's position — that would make it reprocess history
        // it has already merged. Only advance actors that lag behind the cleanup point.
        if let current = userDefault.lastHistoryTransactionTimestamp(for: actor), current >= timestamp { return }
        userDefault.updateLastHistoryTransactionTimestamp(for: actor, to: timestamp)
    }
}

final class PersistentHistoryTrackerManager: @unchecked Sendable {
    init(container: NSPersistentContainer, currentActor: AppPersistentActor, viewBackupContext: NSManagedObjectContext?) {
        self.container = container
        self.currentActor = currentActor
        self.viewBackupContext = viewBackupContext
        self.userDefaults = UserDefaults(suiteName: UserDefaults.appGroupString)!

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                self?.processor()
            }
            .store(in: &cancellables)
    }

    let container: NSPersistentContainer
    let currentActor: AppPersistentActor
    let viewBackupContext: NSManagedObjectContext?
    let userDefaults: UserDefaults

    lazy var backgroundContext = { container.newBackgroundContext() }()

    private var cancellables: Set<AnyCancellable> = []

    private func processor() {
        let fromDate = loadDate()

        backgroundContext.performAndWait {
            do {
                let transactions = try fetcher(date: fromDate)
                if transactions.isEmpty {
                    // Update timestamp to now even when empty, so we don't keep checking from distantPast
                    if fromDate == Date.distantPast {
                        self.userDefaults.updateLastHistoryTransactionTimestamp(for: self.currentActor, to: Date())
                        Logger.persistentHistory.info("Initialized history timestamp for \(self.currentActor.rawValue)")
                    }
                    // Don't log when empty - reduces noise
                } else {
                    merger(transaction: transactions)
                    Logger.persistentHistory.info("Processed \(transactions.count, privacy: .public) transactions")
                }
            } catch {
                Logger.persistentHistory.error("Failed to fetch history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension PersistentHistoryTrackerManager {
    enum Error: String, Swift.Error {
        case historyTransactionConvertionFailed
    }

    func fetcher(date fromDate: Date) throws -> [NSPersistentHistoryTransaction] {
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
    
    func loadDate() -> Date {
        userDefaults.lastHistoryTransactionTimestamp(for: currentActor) ?? Date.distantPast
    }
}

extension PersistentHistoryTrackerManager {
    func merger(transaction: [NSPersistentHistoryTransaction]) {
        guard let viewContext = viewBackupContext else { return }
        viewContext.perform {
            transaction.forEach { transaction in
                let userInfo = transaction.objectIDNotification().userInfo ?? [:]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [viewContext])
            }
        }

        guard let lastTimestamp = transaction.last?.timestamp else { return }
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
