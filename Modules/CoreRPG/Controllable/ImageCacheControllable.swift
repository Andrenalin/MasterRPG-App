// @copyright André Trettin

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The identical property skeleton every `ImageCacheControllable` conformer used to hand-wire
/// itself: two `ImageCacheController` instances, the shared `ObservableImageCache`, and the
/// optional `FileUrlDataController`. Each module still needs its own concrete `CacheController`
/// type (protocol conformance requires one per module, and `createThumbnail`'s body is genuinely
/// module-specific), but now only needs to store one `cacheStorage` value instead of
/// re-declaring and re-initializing all four properties by hand. See CODE_AUDIT §9.3.
public struct ImageCacheControllableStorage: Sendable {
    @MainActor
    public init(fileUrlDataController: FileUrlDataController? = nil) {
        imageCacheController = ImageCacheController()
        thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = fileUrlDataController
        observableImageCache = ObservableImageCache()
    }

    public let imageCacheController: ImageCacheController
    public let thumbnailCacheController: ImageCacheController
    public let fileUrlDataController: FileUrlDataController?
    public let observableImageCache: ObservableImageCache
}

public protocol ImageCacheControllable: Sendable {
    var cacheStorage: ImageCacheControllableStorage { get }

    @MainActor func createImage(for itemId: UUID, item: any ItemDataAccessible) async
    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessible) async
}

extension ImageCacheControllable {
    public var imageCacheController: ImageCacheController { cacheStorage.imageCacheController }
    public var thumbnailCacheController: ImageCacheController { cacheStorage.thumbnailCacheController }
    public var fileUrlDataController: FileUrlDataController? { cacheStorage.fileUrlDataController }

    // Observable cache for SwiftUI views
    @MainActor public var observableImageCache: ObservableImageCache { cacheStorage.observableImageCache }

    @MainActor public func createImage(for itemId: UUID, item: any ItemDataAccessible) async {}

    public func photo(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        PerformanceTrace.cacheEvent(
            hit: image != nil,
            itemId: itemId,
            kind: "full",
            source: "memory"
        )
        return image?.sizeResetCopy()
    }
    
    /// PNG data of the item's thumbnail, generating it first when it is not cached yet.
    ///
    /// For modules that only render QuickLook thumbnails (Pdf, Space) and so never fill the
    /// full-image cache `photo(for:)` reads. See CODE_AUDIT §5.9.
    @MainActor public func thumbnailPngData(for itemId: UUID, item: any ItemDataAccessible) async throws -> Data {
        _ = await thumbnailId(for: itemId, item: item)
        guard let image = await thumbnail(for: itemId) else {
            throw AKImageEncodingError()
        }
        return try image.pngRepresentationData()
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
    /// once it has an image (or `nil`, in which case this is a no-op).
    public func cacheThumbnail(_ thumbnail: AKImage?, for itemId: UUID) async {
        guard let thumbnail else { return }
        await thumbnailCacheController.saveToDisk(thumbnail, for: itemId)
        await thumbnailCacheController.setObject(thumbnail, for: itemId)
    }

    /// Shared by file-backed modules whose thumbnail is just a QuickLook
    /// preview of the on-disk file at a fixed canvas size. Not a default for
    /// the base protocol requirement itself, since other modules' thumbnails
    /// aren't QuickLook-generated at all — `QuickLookThumbnailProviding`
    /// below builds the actual `createThumbnail(for:item:)` default on top
    /// of this for the conformers that are. See CODE_AUDIT_10 §9.12.
    @MainActor
    public func createQuickLookThumbnail(
        for itemId: UUID,
        item: any ItemDataAccessible,
        size: CGSize,
        removeWhiteBackground: Bool = false
    ) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            await AKImage.quickLookThumbnail(for: url, size: size, removeWhiteBackground: removeWhiteBackground)
        }
        await cacheThumbnail(thumbnail, for: itemId)
    }
}

/// Opt-in sub-protocol for conformers whose thumbnail is a QuickLook preview render at a
/// fixed canvas size — PdfRPG's and SpaceRPG's `CacheController`s previously each
/// hand-duplicated an identical `createThumbnail(for:item:)` body, differing only in
/// `quickLookThumbnailSize`/`removesWhiteBackgroundInThumbnail`. See CODE_AUDIT §9.6.
public protocol QuickLookThumbnailProviding: ImageCacheControllable {
    static var quickLookThumbnailSize: CGSize { get }
    static var removesWhiteBackgroundInThumbnail: Bool { get }
}

public extension QuickLookThumbnailProviding {
    static var removesWhiteBackgroundInThumbnail: Bool { false }

    @MainActor
    func createThumbnail(for itemId: UUID, item: any ItemDataAccessible) async {
        await createQuickLookThumbnail(for: itemId, item: item, size: Self.quickLookThumbnailSize, removeWhiteBackground: Self.removesWhiteBackgroundInThumbnail)
    }
}

extension ImageCacheControllable {
    public func remove(itemId: UUID, includeImage: Bool = true) async {
        if includeImage {
            await imageCacheController.removeObject(for: itemId)
        }
        await thumbnailCacheController.removeObject(for: itemId)
        await observableImageCache.reset(for: itemId, includeImage: includeImage)
    }
    
    @discardableResult
    @MainActor public func photoId(for itemId: UUID, item: any ItemDataAccessible, shouldDownload: Bool = false) async -> UUID? {
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
    public func thumbnailId(for itemId: UUID, item: any ItemDataAccessible) async -> UUID? {
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
///
/// Bounded LRU by count — unlike the actor-isolated `ImageCacheController` (NSCache-backed,
/// 2,500-object/256MB bound — see `ObjectCache`), this cache used to be a plain, unevicted
/// dictionary that only shrank on item deletion, growing unboundedly for the app session's
/// lifetime (every full-resolution image ever displayed stayed resident). See CODE_AUDIT_9 §7.1.
@MainActor @Observable
public final class ObservableImageCache: Sendable {
    public init() {}

    /// Full images are the expensive ones (decompressed, uncapped resolution), so this stays
    /// small; thumbnails are cheap and shown in list rows, so a larger bound is fine.
    private static let imageCountLimit = 120
    private static let thumbnailCountLimit = 400

    private var imageCache: [UUID: AKImage] = [:]
    private var imageOrder: [UUID] = []
    private var thumbnailCache: [UUID: AKImage] = [:]
    private var thumbnailOrder: [UUID] = []

    public func image(for itemId: UUID) -> AKImage? {
        imageCache[itemId]
    }

    public func thumbnail(for itemId: UUID) -> AKImage? {
        thumbnailCache[itemId]
    }

    public func setImage(_ image: AKImage?, for itemId: UUID) {
        guard let image else {
            removeImage(for: itemId)
            return
        }
        touch(itemId, in: &imageOrder, isNew: imageCache[itemId] == nil)
        imageCache[itemId] = image
        evictLeastRecentlyUsed(cache: &imageCache, order: &imageOrder, limit: Self.imageCountLimit)
    }

    public func setThumbnail(_ image: AKImage?, for itemId: UUID) {
        guard let image else {
            removeThumbnail(for: itemId)
            return
        }
        touch(itemId, in: &thumbnailOrder, isNew: thumbnailCache[itemId] == nil)
        thumbnailCache[itemId] = image
        evictLeastRecentlyUsed(cache: &thumbnailCache, order: &thumbnailOrder, limit: Self.thumbnailCountLimit)
    }

    public func removeImage(for itemId: UUID) {
        imageCache.removeValue(forKey: itemId)
        imageOrder.removeAll { $0 == itemId }
    }

    public func removeThumbnail(for itemId: UUID) {
        thumbnailCache.removeValue(forKey: itemId)
        thumbnailOrder.removeAll { $0 == itemId }
    }

    public func reset(for itemId: UUID, includeImage: Bool = true) {
        if includeImage {
            removeImage(for: itemId)
        }
        removeThumbnail(for: itemId)
    }

    /// Marks `itemId` as most-recently-used, appending it to `order` if it isn't tracked yet.
    private func touch(_ itemId: UUID, in order: inout [UUID], isNew: Bool) {
        if !isNew {
            order.removeAll { $0 == itemId }
        }
        order.append(itemId)
    }

    /// Drops the least-recently-used entries until `cache`/`order` are back at `limit`.
    private func evictLeastRecentlyUsed(cache: inout [UUID: AKImage], order: inout [UUID], limit: Int) {
        while order.count > limit {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
