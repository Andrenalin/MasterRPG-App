// @copyright André Trettin


#if os(macOS)
import AppKit
#else
import UIKit
#endif

import Foundation

public struct ImageCacheController: Sendable {
    public init() {}
    
    private let cache = ObjectCache<AKImage>()
    
    public func hasObject(for itemId: UUID) async -> Bool {
        await cache.hasObject(for: itemId)
    }
    
    public func object(for itemId: UUID) async -> AKImage? {
        await cache.cachedObject(for: itemId)
    }
    
    public func removeObject(for itemId: UUID) async {
        await cache.removeObject(for: itemId)
        await cache.removeFromDisk(for: itemId)
    }
    
    public func setObject(_ object: AKImage, for itemId: UUID) async {
        let cost = Int(object.size.width * object.size.height * 4)
        await cache.insertObject(object, for: itemId, cost: cost)
    }
    
    public func loadFromDisk(for itemId: UUID) async -> AKImage? {
        await cache.loadImageFromDisk(for: itemId)
    }

    public func saveToDisk(_ object: AKImage, for itemId: UUID) async {
        await cache.saveImageToDisk(object, for: itemId)
    }
}
