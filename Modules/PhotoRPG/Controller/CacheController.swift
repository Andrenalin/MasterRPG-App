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
    init(fileUrlDataController: FileUrlDataController) {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = fileUrlDataController
    }
    
    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
}

extension CacheController: ImageCacheControllable {
    func createImage(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl  else { return }
        let image: AKImage?
        if let data = fileUrl.data {
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

    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        let cachedImage = await imageCacheController.object(for: itemId)
        if cachedImage == nil {
            await createImage(for: itemId, item: item)
        }
        guard let image = await imageCacheController.object(for: itemId) else { return }
        let thumbnail = await image.resize(to: CGSize(width: 64, height: 64), topAligned: true)
        if let thumbnail {
            await thumbnailCacheController.saveToDisk(thumbnail, for: itemId)
            await thumbnailCacheController.setObject(thumbnail, for: itemId)
        }
    }
}
