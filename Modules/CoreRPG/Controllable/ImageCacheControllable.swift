// @copyright André Trettin

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public protocol ImageCacheControllable: Sendable {
    var imageCacheController: ImageCacheController { get }
    var thumbnailCacheController: ImageCacheController { get }
    var fileUrlDataController: FileUrlDataController? { get }
    
    // Observable cache for SwiftUI views
    @MainActor var observableImageCache: ObservableImageCache { get }

    @MainActor func createImage(for itemId: UUID, item: any ItemDataAccessable) async
    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async
}

extension ImageCacheControllable {
    @MainActor public func createImage(for itemId: UUID, item: any ItemDataAccessable) async {}
    
    public func photo(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        PerformanceTrace.cacheEvent(
            hit: image != nil,
            itemId: itemId,
            kind: "full",
            source: "memory"
        )
        image?.resetSize()
        return image
    }
    
    public func thumbnail(for itemId: UUID) async -> AKImage? {
        guard let image = await thumbnailCacheController.object(for: itemId) else {
            PerformanceTrace.cacheEvent(
                hit: false,
                itemId: itemId,
                kind: "thumbnail",
                source: "memory"
            )
            guard let fileImage = await thumbnailCacheController.loadFromDisk(for: itemId) else {
                PerformanceTrace.cacheEvent(
                    hit: false,
                    itemId: itemId,
                    kind: "thumbnail",
                    source: "disk"
                )
                return nil
            }
            PerformanceTrace.cacheEvent(
                hit: true,
                itemId: itemId,
                kind: "thumbnail",
                source: "disk"
            )
            await thumbnailCacheController.setObject(fileImage, for: itemId)
            return fileImage
        }
        PerformanceTrace.cacheEvent(
            hit: true,
            itemId: itemId,
            kind: "thumbnail",
            source: "memory"
        )
        return image
    }
    
    /// Persists a generated thumbnail to disk and the in-memory cache together —
    /// the common tail every module's `createThumbnail(for:item:)` ends with,
    /// once it has an image (or `nil`, in which case this is a no-op). See
    /// CODE_AUDIT §9.7.
    public func cacheThumbnail(_ thumbnail: AKImage?, for itemId: UUID) async {
        guard let thumbnail else { return }
        await thumbnailCacheController.saveToDisk(thumbnail, for: itemId)
        await thumbnailCacheController.setObject(thumbnail, for: itemId)
    }

    public func remove(itemId: UUID, includeImage: Bool = true) async {
        if includeImage {
            await imageCacheController.removeObject(for: itemId)
        }
        await thumbnailCacheController.removeObject(for: itemId)
        await observableImageCache.reset(for: itemId, includeImage: includeImage)
    }
    
    @discardableResult
    @MainActor public func photoId(for itemId: UUID, item: any ItemDataAccessable, shouldDownload: Bool = false) async -> UUID? {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return nil }
        let trace = PerformanceTrace.begin("FullImagePipeline", itemId: itemId, kind: "full")
        defer { trace?.end() }
        if await imageCacheController.hasObject(for: itemId) {
            PerformanceTrace.cacheEvent(
                hit: true,
                itemId: itemId,
                kind: "full",
                source: "memory"
            )
            return itemId
        }
        PerformanceTrace.cacheEvent(
            hit: false,
            itemId: itemId,
            kind: "full",
            source: "memory"
        )
        guard !Task.isCancelled else { return nil }
        if shouldDownload {
            if await fileUrlDataController.hasAccess(for: fileUrl) == false {
                try? await fileUrlDataController.download(fileUrl: fileUrl)
                await thumbnailCacheController.removeObject(for: itemId)
            }
        } else if await !fileUrlDataController.isAvailableWithoutDownloading(fileUrl) {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        await createImage(for: itemId, item: item)
        return await imageCacheController.hasObject(for: itemId) ? itemId : nil
    }
        
    @discardableResult
    public func thumbnailId(for itemId: UUID, item: any ItemDataAccessable) async -> UUID? {
        let trace = PerformanceTrace.begin("ThumbnailPipeline", itemId: itemId, kind: "thumbnail")
        defer { trace?.end() }
        if await thumbnailCacheController.hasObject(for: itemId) {
            PerformanceTrace.cacheEvent(
                hit: true,
                itemId: itemId,
                kind: "thumbnail",
                source: "memory"
            )
            return itemId
        }
        let _ = await thumbnail(for: itemId) // load from disk
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        guard !Task.isCancelled else { return nil }
        if let fileUrlDataController, let fileUrl = await item.fileUrl,
           await !fileUrlDataController.isAvailableWithoutDownloading(fileUrl) {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        await createThumbnail(for: itemId, item: item)
        return await thumbnailCacheController.hasObject(for: itemId) ? itemId : nil
    }
    
    // MARK: - Observable Cache Helpers
    
    /// Get cached image synchronously for SwiftUI views
    @MainActor
    public func cachedImage(for itemId: UUID) -> AKImage? {
        observableImageCache.image(for: itemId)
    }
    
    /// Get cached thumbnail synchronously for SwiftUI views
    @MainActor
    public func cachedThumbnail(for itemId: UUID) -> AKImage? {
        observableImageCache.thumbnail(for: itemId)
    }
    
    /// Set cached image (called after async load completes)
    @MainActor
    public func setCachedImage(_ image: AKImage?, for itemId: UUID) {
        observableImageCache.setImage(image, for: itemId)
    }
    
    /// Set cached thumbnail (called after async load completes)
    @MainActor
    public func setCachedThumbnail(_ image: AKImage?, for itemId: UUID) {
        observableImageCache.setThumbnail(image, for: itemId)
    }
}

// MARK: - Observable Image Cache

/// Observable cache for synchronous image access in SwiftUI views
/// This bridges the async ImageCacheController with SwiftUI's synchronous observation
@MainActor @Observable
public final class ObservableImageCache: Sendable {
    public init() {}
    
    private var imageCache: [UUID: AKImage] = [:]
    private var thumbnailCache: [UUID: AKImage] = [:]
    
    public func image(for itemId: UUID) -> AKImage? {
        imageCache[itemId]
    }
    
    public func thumbnail(for itemId: UUID) -> AKImage? {
        thumbnailCache[itemId]
    }
    
    public func setImage(_ image: AKImage?, for itemId: UUID) {
        imageCache[itemId] = image
    }
    
    public func setThumbnail(_ image: AKImage?, for itemId: UUID) {
        thumbnailCache[itemId] = image
    }
    
    public func removeImage(for itemId: UUID) {
        imageCache.removeValue(forKey: itemId)
    }
    
    public func removeThumbnail(for itemId: UUID) {
        thumbnailCache.removeValue(forKey: itemId)
    }
    
    public func reset(for itemId: UUID, includeImage: Bool = true) {
        if includeImage {
            removeImage(for: itemId)
        }
        removeThumbnail(for: itemId)
    }
}
