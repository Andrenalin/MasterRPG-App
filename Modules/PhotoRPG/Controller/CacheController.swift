// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CacheController: Sendable {
    @MainActor init(fileUrlDataController: FileUrlDataController) {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = fileUrlDataController
        self.observableImageCache = ObservableImageCache()
    }
    
    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
    let observableImageCache: ObservableImageCache
}

extension CacheController: ImageCacheControllable {
    @MainActor func createImage(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl  else { return }
        let trace = PerformanceTrace.begin("ImageDecode", itemId: itemId, kind: "full")
        defer { trace?.end() }
        let image: AKImage?
        if let data = fileUrl.data {
            image = AKImage(data: data)
        } else if let data = try? await fileUrlDataController.loadData(for: fileUrl) {
            image = AKImage(data: data)
        } else {
            image = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
                guard let url else { return nil }
                return AKImage(contentsOfFile: url.relativePath)
            }
        }
        if let image {
            await imageCacheController.setObject(image, for: itemId)
        } else {
            Logger.cacheController.warning("Cannot get image \(itemId, privacy: .public)")
        }
    }

    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        let trace = PerformanceTrace.begin("ThumbnailGenerate", itemId: itemId, kind: "thumbnail")
        defer { trace?.end() }
        // Reuse an already fully-decoded image if one happens to be cached; otherwise
        // decode a downsampled ImageIO thumbnail directly, avoiding a full-resolution
        // decode purely to throw almost all of it away.
        let source: AKImage?
        if let cachedImage = await imageCacheController.object(for: itemId) {
            source = cachedImage
        } else {
            source = await downsampledSource(for: itemId, item: item)
        }
        guard let source else { return }
        let thumbnail = await source.resize(to: CGSize(width: 64, height: 64), topAligned: true)
        await cacheThumbnail(thumbnail, for: itemId)
    }

    /// ImageIO thumbnail max pixel size: comfortably above the 64pt target at the
    /// highest device scale (`resize(to:)` renders up to 3x on iOS).
    private static let thumbnailMaxPixelSize: CGFloat = 256

    @MainActor private func downsampledSource(for itemId: UUID, item: any ItemDataAccessable) async -> AKImage? {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return nil }
        if let data = fileUrl.data {
            return AKImage.downsampledThumbnail(from: data, maxPixelSize: Self.thumbnailMaxPixelSize)
        }
        if let data = try? await fileUrlDataController.loadData(for: fileUrl) {
            return AKImage.downsampledThumbnail(from: data, maxPixelSize: Self.thumbnailMaxPixelSize)
        }
        return await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            guard let url else { return nil }
            return AKImage.downsampledThumbnail(from: url, maxPixelSize: Self.thumbnailMaxPixelSize)
        }
    }
}
