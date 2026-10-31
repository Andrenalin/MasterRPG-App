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

    /// No attribute set for a trashed item or an entry of one, so trashed content leaves the index
    /// when it is trashed and comes back when it is restored. See CODE_AUDIT_Since_3.0.1 §5.6.
    public override func attributeSet(for object: NSManagedObject) -> CSSearchableItemAttributeSet? {
        guard let objectAttribute = object as? SpotlightIndexerAttribute,
              !SpotlightActivityRoute.isTrashed(object) else { return nil }
        return objectAttribute.attributeSet()
    }

    /// Bump when `attributeSet()` changes what the rows carry. The delegate re-donates only the
    /// objects that changed in the persistent history, so rows that are never saved again keep the
    /// attribute set they were first donated with.
    private static let indexVersion = 2
    private static let indexVersionKey = "spotlightCoreDataIndexVersion"

    /// Starts indexing; first deletes the index once per `indexVersion`, so every row is donated
    /// again with the current attribute set. The deletion only touches this delegate's index
    /// (`indexName()`), not the App Entity donations.
    public func startIndexing() async {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: Self.indexVersionKey) < Self.indexVersion {
            do {
                try await deleteSpotlightIndex()
                defaults.set(Self.indexVersion, forKey: Self.indexVersionKey)
            } catch {
                // Keep the old version so the next launch tries again.
            }
        }
        startSpotlightIndexing()
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
    
    public func startIndexing() async {}

    public func observeIndexing() {}

    public func stopSpotlightIndexing() {}
}
#endif
