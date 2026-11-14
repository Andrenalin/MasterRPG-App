// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif


public actor ObjectCache<Object: AnyObject & Sendable> {
    public init(countLimit: Int = 2500) {
        self.countLimit = countLimit
    }

    private lazy var objectCache: NSCache<AnyObject, AnyObject> = {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.countLimit = countLimit
        cache.totalCostLimit = 256 * ByteUnit.mebibyte
        return cache
    }()

    private let countLimit: Int

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
    }

    public func removeObject(for itemId: UUID) {
        objectCache.removeObject(forKey: itemId as AnyObject)
    }
        
    // MARK: - File Cache

    // The disk methods read nothing from the actor, so they run off it: a slow file read or a
    // JPEG encode must not hold up the memory hits of every module's image cache behind it.
    // See CODE_AUDIT §3.1.

    @concurrent
    public nonisolated func removeFromDisk(for itemId: UUID) async {
        let url = fileURL(for: itemId)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent
    public nonisolated func loadImageFromDisk(for itemId: UUID) async -> AKImage? {
        let url = fileURL(for: itemId)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return AKImage(data: data)
    }

    @concurrent
    public nonisolated func saveImageToDisk(_ image: AKImage, for itemId: UUID) async {
        ensureCacheDirectoryExists(for: itemId)
        let url = fileURL(for: itemId)
        
        guard let data = image.jpegData(compressionQuality: JPEGQuality.cachedThumbnail) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    // MARK: - Disk cache helpers
    
    private nonisolated var cacheDirectoryURL: URL {
        URL.cachesDirectory.appending(path: "ImageCache", directoryHint: .isDirectory)
    }

    private nonisolated func subDirURL(for itemId: UUID) -> URL {
        cacheDirectoryURL
            .appending(path: String(itemId.uuidString.suffix(2)))
    }

    private nonisolated func fileURL(for itemId: UUID) -> URL {
        subDirURL(for: itemId)
            .appending(path: itemId.uuidString)
            .appendingPathExtension("jpg")
    }
    
    /// Ensures the cache directory exists.
    private nonisolated func ensureCacheDirectoryExists(for itemId: UUID) {
        let dir = subDirURL(for: itemId)
        if !FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
