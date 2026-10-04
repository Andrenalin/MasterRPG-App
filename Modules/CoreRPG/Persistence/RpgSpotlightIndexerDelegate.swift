// @copyright André Trettin

import Foundation
import CoreData
import CoreSpotlight

public protocol SpotlightIndexerAttribute {
#if !os(tvOS)
    func attributeSet() -> CSSearchableItemAttributeSet
#endif
}

@MainActor @Observable
public final class RpgSpotlightIndexerModel: Sendable {
    public nonisolated init() {}

    public private(set) var message: String?
    
    nonisolated func reset(message: String) {
        Task { @MainActor in
            self.message = message
        }
    }
}

#if !os(tvOS)
public final class RpgSpotlightIndexerDelegate: NSCoreDataCoreSpotlightDelegate {
    public let model: RpgSpotlightIndexerModel = RpgSpotlightIndexerModel()

    /// Replaces the previous closure-based `addObserver(forName:object:queue:using:)`
    /// token with a `Task` iterating the async `notifications(named:)` sequence —
    /// cancelling it is the direct equivalent of the old `removeObserver(_:)` call.
    /// See CODE_AUDIT_9 §4.4.
    private var indexingTask: Task<Void, Never>?

    /// The notification sequence never finishes, so a replaced delegate (Cloud/Local switch,
    /// recovery) would otherwise keep its loop alive for the process lifetime.
    /// See CODE_AUDIT_16 §3.16.
    deinit {
        indexingTask?.cancel()
    }

    public override func domainIdentifier() -> String {
        BundleIds.product
    }

    public override func indexName() -> String? {
        "masterRPG-index"
    }

    public override func attributeSet(for object: NSManagedObject) -> CSSearchableItemAttributeSet? {
        guard let objectAttribute = object as? SpotlightIndexerAttribute else { return nil }
        return objectAttribute.attributeSet()
    }

    public func observeIndexing() {
        if isIndexingEnabled && indexingTask == nil {
            let model = model
            indexingTask = Task {
                for await notification in NotificationCenter.default.notifications(named: NSCoreDataCoreSpotlightDelegate.indexDidUpdateNotification) {
                    let userInfo = notification.userInfo
                    let storeId = userInfo?[NSStoreUUIDKey] as? String
                    let token = userInfo?[NSPersistentHistoryTokenKey] as? NSPersistentHistoryToken
                    if let storeId = storeId, let token = token {
                        model.reset(message: "Store with identifier \(storeId) has completed indexing and has processed history token up through \(String(describing: token)).")
                    }
                }
            }
        } else {
            guard indexingTask != nil else { return }
            indexingTask?.cancel()
            indexingTask = nil
        }
    }
}

#else
public final class RpgSpotlightIndexerDelegate {
    public let model: RpgSpotlightIndexerModel = RpgSpotlightIndexerModel()
    
    public func observeIndexing() {}

    public func stopSpotlightIndexing() {}
}
#endif
