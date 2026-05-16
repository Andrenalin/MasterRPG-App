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

    func createImage(for itemId: UUID, item: any ItemDataAccessable) async
    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async
}

extension ImageCacheControllable {
    public func createImage(for itemId: UUID, item: any ItemDataAccessable) async {}
    
    public func photo(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        image?.resetSize()
        return image
    }
    
    public func thumbnail(for itemId: UUID) async -> AKImage? {
        guard let image = await thumbnailCacheController.object(for: itemId) else {
            guard let fileImage = await thumbnailCacheController.loadFromDisk(for: itemId) else {
                return nil
            }
            await thumbnailCacheController.setObject(fileImage, for: itemId)
            return fileImage
        }
        return image
    }
    
    public func remove(itemId: UUID, includeImage: Bool = true) async {
        if includeImage {
            await imageCacheController.removeObject(for: itemId)
        }
        await thumbnailCacheController.removeObject(for: itemId)
        await observableImageCache.reset(for: itemId, includeImage: includeImage)
    }
    
    @discardableResult
    public func photoId(for itemId: UUID, item: any ItemDataAccessable, shouldDownload: Bool = false) async -> UUID? {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return nil }
        guard await !imageCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task(priority: .userInitiated) {
            if shouldDownload {
                if await fileUrlDataController.hasAccess(for: fileUrl) == false {
                    try? await fileUrlDataController.download(fileUrl: fileUrl)
                    await thumbnailCacheController.removeObject(for: itemId)
                }
            }
            await self.createImage(for: itemId, item: item)
        }
        _ = await imageTask.value
        return await imageCacheController.hasObject(for: itemId) ? itemId : nil
    }
        
    @discardableResult
    public func thumbnailId(for itemId: UUID, item: any ItemDataAccessable) async -> UUID? {
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let _ = await thumbnail(for: itemId) // load from disk
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task(priority: .userInitiated) {
            await self.createThumbnail(for: itemId, item: item)
        }
        _ = await imageTask.value
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

