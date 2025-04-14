// @copyright André Trettin

import Foundation
import Combine
import CoreData
import CoreSpotlight

@Observable
public final class RpgSpotlightIndexerModel: @unchecked Sendable {
    public var message: String?
}

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
//        if let photo = object as? Photo {
//            let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
//            attributeSet.identifier = photo.uniqueName
//            attributeSet.displayName = photo.userSpecifiedName
//            attributeSet.thumbnailData = photo.thumbnail?.data
//
//            for case let tag as Tag in photo.tags ?? [] {
//                if let name = tag.name {
//                    if attributeSet.keywords != nil {
//                        attributeSet.keywords?.append(name)
//                    } else {
//                        attributeSet.keywords = [name]
//                    }
//                }
//            }
//
//            return attributeSet
//        } else if let tag = object as? Tag {
//            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
//            attributeSet.displayName = tag.name
//            return attributeSet
//        }

        return nil
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
                    print("Store with identifier \(storeID) has completed ",
                          "indexing and has processed history token up through \(String(describing: token)).")
                    model?.message = "Store with identifier \(storeID) has completed indexing and has processed history token up through \(String(describing: token))."
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
