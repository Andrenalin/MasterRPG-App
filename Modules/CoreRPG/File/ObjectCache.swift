// @copyright André Trettin

import Foundation

actor ObjectCache<Object: AnyObject> {
    init(countLimit: Int = 500) {
        self.countLimit = countLimit
    }

    private lazy var objectCache: NSCache<AnyObject, AnyObject> = {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.countLimit = countLimit
        return cache
    }()

    private let lock = NSLock()
    private let countLimit: Int

    public private(set) var allKeys: Set<UUID> = Set()

    public func hasObject(for itemId: UUID) -> Bool {
        (objectCache.object(forKey: itemId as AnyObject) as? Object) != nil
    }

    public func cachedObject(for itemId: UUID) -> Object? {
        objectCache.object(forKey: itemId as AnyObject) as? Object
    }

    public func insertObject(_ object: Object?, for itemId: UUID) {
        guard let object = object else { return removeObject(for: itemId) }
        objectCache.setObject(object as AnyObject, forKey: itemId as AnyObject)
        allKeys.insert(itemId)
    }

    public func removeObject(for itemId: UUID) {
        objectCache.removeObject(forKey: itemId as AnyObject)
        allKeys.remove(itemId)
    }

    public subscript(_ itemId: UUID) -> Object? {
        get { cachedObject(for: itemId) }
        set { insertObject(newValue, for: itemId) }
    }
}
