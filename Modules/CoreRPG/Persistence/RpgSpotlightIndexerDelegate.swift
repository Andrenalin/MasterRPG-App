// @copyright André Trettin

import Foundation
import Combine
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
        
    var observables: AnyObject?
        
    public override func domainIdentifier() -> String {
        "de.andretrettin.gamemaster"
    }

    public override func indexName() -> String? {
        "masterRPG-index"
    }
    
    public override func attributeSet(for object: NSManagedObject) -> CSSearchableItemAttributeSet? {
        guard let objectAttritube = object as? SpotlightIndexerAttribute else { return nil }
        return objectAttritube.attributeSet()
    }
    
    public func observeIndexing() {
        let center = NotificationCenter.default
        if isIndexingEnabled && observables == nil {
            let queue = OperationQueue.main
            observables = center.addObserver(forName: NSCoreDataCoreSpotlightDelegate.indexDidUpdateNotification,
                                                         object: nil,
                                             queue: queue) { [weak model] (notification) in
                let userInfo = notification.userInfo
                let storeID = userInfo?[NSStoreUUIDKey] as? String
                let token = userInfo?[NSPersistentHistoryTokenKey] as? NSPersistentHistoryToken
                if let storeID = storeID, let token = token {
                    model?.reset(message: "Store with identifier \(storeID) has completed indexing and has processed history token up through \(String(describing: token)).")
                }
            }
        } else {
            if observables == nil {
                return
            }
            center.removeObserver(observables as Any)
        }
    }
}

#else
public final class RpgSpotlightIndexerDelegate {
    public let model: RpgSpotlightIndexerModel = RpgSpotlightIndexerModel()
    
    public func observeIndexing() {}
}
#endif
