// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif


public actor ObjectCache<Object: AnyObject> {
    public init(countLimit: Int = 2500) {
        self.countLimit = countLimit
    }

    private lazy var objectCache: NSCache<AnyObject, AnyObject> = {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.countLimit = countLimit
        cache.totalCostLimit = 128_000_000
        return cache
    }()

    private let countLimit: Int

    public private(set) var allKeys: Set<UUID> = Set()

    // MARK: - Memory Cache
    
    public func hasObject(for itemId: UUID) -> Bool {
        (objectCache.object(forKey: itemId as AnyObject) as? Object) != nil
    }

    public func cachedObject(for itemId: UUID) -> Object? {
        objectCache.object(forKey: itemId as AnyObject) as? Object
    }

    public func insertObject(_ object: Object?, for itemId: UUID, cost: Int) {
        guard let object = object else { return removeObject(for: itemId) }
        objectCache.setObject(object as AnyObject, forKey: itemId as AnyObject, cost: cost)
        allKeys.insert(itemId)
    }

    public func removeObject(for itemId: UUID) {
        objectCache.removeObject(forKey: itemId as AnyObject)
        allKeys.remove(itemId)
    }
        
    // MARK: - File Cache

    public func removeFromDisk(for itemId: UUID) {
        let url = fileURL(for: itemId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func loadImageFromDisk(for itemId: UUID) -> AKImage? {
        let url = fileURL(for: itemId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return AKImage(data: data)
    }
    
    public func saveImageToDisk(_ image: AKImage, for itemId: UUID) {
        ensureCacheDirectoryExists(for: itemId)
        let url = fileURL(for: itemId)
        
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
//        #if os(macOS)
//        guard
//            let tiffData = image.tiffRepresentation,
//            let bitmap = NSBitmapImageRep(data: tiffData),
//            let data = bitmap.representation(using: .jpeg, properties: [:]) ??
//                       bitmap.representation(using: .png, properties: [:])
//        else { return }
//        #else
//        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
//            return
//        }
//        #endif
        
        try? data.write(to: url, options: .atomic)
    }
    
    // MARK: - Disk cache helpers
    
    private var cacheDirectoryURL: URL {
        URL.cachesDirectory.appendingPathComponent("ImageCache", isDirectory: true)
    }

    private func subDirURL(for itemId: UUID) -> URL {
        cacheDirectoryURL
            .appendingPathComponent(String(itemId.uuidString.suffix(2)))
    }

    private func fileURL(for itemId: UUID) -> URL {
        subDirURL(for: itemId)
            .appendingPathComponent(itemId.uuidString)
            .appendingPathExtension("jpg")
    }
    
    /// Ensures the cache directory exists.
    private func ensureCacheDirectoryExists(for itemId: UUID) {
        let dir = subDirURL(for: itemId)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
