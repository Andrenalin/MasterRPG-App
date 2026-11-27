// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif


public actor ObjectCache<Object: AnyObject & Sendable> {
    /// `costLimit` bounds the decoded bytes, `diskDirectoryName` is the folder in Caches the
    /// disk copies go to: full images and thumbnails used to share one file per item id, so
    /// removing a full image deleted its thumbnail. See CODE_AUDIT_29 §7.3.
    public init(countLimit: Int = 2500, costLimit: Int = 128 * ByteUnit.mebibyte, diskDirectoryName: String = "ImageCache") {
        self.countLimit = countLimit
        self.costLimit = costLimit
        self.diskDirectoryName = diskDirectoryName
#if !os(macOS)
        // NSCache does not reliably empty itself on a memory warning; the observable caches
        // were the only ones trimmed. See CODE_AUDIT_29 §7.3.
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard let self else { return }
                await self.removeAllObjects()
            }
        }
#endif
    }

    private lazy var objectCache: NSCache<AnyObject, AnyObject> = {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.countLimit = countLimit
        cache.totalCostLimit = costLimit
        return cache
    }()

    private let countLimit: Int
    private let costLimit: Int
    private let diskDirectoryName: String

    /// Empties the memory cache; the disk copies stay.
    public func removeAllObjects() {
        objectCache.removeAllObjects()
    }

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
        URL.cachesDirectory.appending(path: diskDirectoryName, directoryHint: .isDirectory)
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
