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
        cacheStorage = ImageCacheControllableStorage(fileUrlDataController: fileUrlDataController)
    }

    let cacheStorage: ImageCacheControllableStorage
}

extension CacheController: ImageCacheControllable {
    @MainActor func createImage(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl  else { return }
        let trace = PerformanceTrace.begin("ImageDecode", itemId: itemId, kind: "full")
        defer { trace?.end() }
        let image = await Self.decodedImage(for: fileUrl, fileUrlDataController: fileUrlDataController)
        if let image {
            await imageCacheController.setObject(image, for: itemId)
        } else {
            Logger.cacheController.warning("Cannot get image \(itemId, privacy: .public)")
        }
    }

    /// Full-resolution image decompression is a blocking, CPU-bound call for large source
    /// images (map backgrounds, character portraits) — `@concurrent` keeps it off the main
    /// actor, matching the pattern already used by `AudioPlayerSession.setActive()`.
    /// See CODE_AUDIT_9 §7.2.
    @concurrent
    private static func decodedImage(for fileUrl: FileUrl, fileUrlDataController: FileUrlDataController) async -> AKImage? {
        await fileUrlDataController.resolvedImage(
            for: fileUrl,
            // Bounded ImageIO decode (forced off-main, capped pixel size); the plain platform
            // decoder stays as the fallback for formats ImageIO cannot report dimensions for.
            // See CODE_AUDIT_17 §7.6.
            decodeData: { AKImage.boundedDecode(from: $0) ?? AKImage(data: $0) },
            decodeUrl: { AKImage.boundedDecode(from: $0) ?? AKImage(contentsOfFile: $0.relativePath) }
        )
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
        let thumbnail = await source.resize(to: Self.thumbnailTargetSize, topAligned: true)
        await cacheThumbnail(thumbnail, for: itemId)
    }

    /// The rendered thumbnail's target point size.
    private static let thumbnailTargetSize = CGSize(width: 64, height: 64)

    /// ImageIO thumbnail max pixel size: comfortably above the 64pt target at the
    /// highest device scale (`resize(to:)` renders up to 3x on iOS).
    private static let thumbnailMaxPixelSize: CGFloat = 256

    @MainActor private func downsampledSource(for itemId: UUID, item: any ItemDataAccessable) async -> AKImage? {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return nil }
        return await fileUrlDataController.resolvedImage(
            for: fileUrl,
            decodeData: { AKImage.downsampledThumbnail(from: $0, maxPixelSize: Self.thumbnailMaxPixelSize) },
            decodeUrl: { AKImage.downsampledThumbnail(from: $0, maxPixelSize: Self.thumbnailMaxPixelSize) }
        )
    }
}
