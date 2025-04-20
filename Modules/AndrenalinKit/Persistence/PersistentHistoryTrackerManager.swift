// @copyright André Trettin

import Combine
import CoreData
import Foundation
import os.log

public enum AppPersistentActor: String, CaseIterable {
    case mainApp
    case sharingExtension
    // extensions that can read / write to the app group core database
    case rpgWidget
}

public struct PersistentHistoryCleaner {
    @MainActor
    public init(container: NSPersistentContainer) {
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

        let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates: [NSPredicate] = []

            appActors.forEach { appActor in
                let perdicate = NSPredicate(format: "%K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue)
                predicates.append(perdicate)
            }

            let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            deleteHistoryRequest.fetchRequest = fetchRequest
        }

        container.performBackgroundTask { context in
            do {
                try context.execute(deleteHistoryRequest)
                Logger.persistentHistory.info("Update Transaction Dates")
                appActors.forEach { actor in
                    userDefault.updateLastHistoryTransactionTimestamp(for: actor, to: nil)
                }
            } catch {
                Logger.persistentHistory.error("Clean History error \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

final class PersistentHistoryTrackerManager {
    init(container: NSPersistentContainer, model: CoreDataInitModel) {
        self.container = container
        self.model = model
        self.userDefaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")!

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator)
            //.subscribe(on: queue, options: nil)
            .sink { [weak self] _ in
                self?.processor()
            }
            .store(in: &cancellables)
    }

    let container: NSPersistentContainer
    let model: CoreDataInitModel
    let userDefaults: UserDefaults

    lazy var backgroundContext = { container.newBackgroundContext() }()

    private var cancellables: Set<AnyCancellable> = []
    private lazy var queue = {
        DispatchQueue(label: "de.andretrettin.\(self.model.currentActor.rawValue).processPersistentHistory")
    }()

    private func processor() {
        backgroundContext.performAndWait {
            guard let transactions = try? fetcher() else {
                Logger.persistentHistory.info("No Transactions")
                return
            }
            merger(transaction: transactions)
            if !transactions.isEmpty {
                Logger.persistentHistory.info("\(transactions.count, privacy: .public) Transactions")
            }
        }
    }
}

extension PersistentHistoryTrackerManager {
    enum Error: String, Swift.Error {
        case historyTransactionConvertionFailed
    }

    func fetcher() throws -> [NSPersistentHistoryTransaction] {
        let fromDate = userDefaults.lastHistoryTransactionTimestamp(for: model.currentActor) ?? Date.distantPast

        let historyFetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: fromDate)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates: [NSPredicate] = []

            AppPersistentActor.allCases.forEach { appActor in
                if appActor == model.currentActor {
                    // own transactions from batchContext others can be ignored
                    let perdicate = NSPredicate(format: "%K = %@ AND %K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue, #keyPath(NSPersistentHistoryTransaction.contextName), "batchContext")
                    predicates.append(perdicate)
                } else {
                    // other actors we need to process
                    let perdicate = NSPredicate(format: "%K = %@", #keyPath(NSPersistentHistoryTransaction.author), appActor.rawValue)
                    predicates.append(perdicate)
                }
            }

            let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            historyFetchRequest.fetchRequest = fetchRequest
        }

        guard let historyResult = try backgroundContext.execute(historyFetchRequest) as? NSPersistentHistoryResult, let history = historyResult.result as? [NSPersistentHistoryTransaction] else { throw Error.historyTransactionConvertionFailed }
        return history
    }
}

extension PersistentHistoryTrackerManager {
    func merger(transaction: [NSPersistentHistoryTransaction]) {
        guard let viewContext = model.context else { return }
        viewContext.perform {
            transaction.forEach { transaction in
                let userInfo = transaction.objectIDNotification().userInfo ?? [:]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [viewContext])
            }
        }

        guard let lastTimestamp = transaction.last?.timestamp else { return }
        userDefaults.updateLastHistoryTransactionTimestamp(for: model.currentActor, to: lastTimestamp)
    }
}

fileprivate extension UserDefaults {
    func lastCommonTransactionTimestamp(in appActors: [AppPersistentActor]) -> Date? {
        let sevenDaysAgo = Date().addingTimeInterval(-7*24*60*60)
        let timestamp = appActors
            .compactMap { lastHistoryTransactionTimestamp(for: $0) }
            .min() ?? sevenDaysAgo
        return max(timestamp, sevenDaysAgo)
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
