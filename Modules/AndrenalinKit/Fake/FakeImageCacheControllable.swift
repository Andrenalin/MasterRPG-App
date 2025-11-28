// @copyright André Trettin

import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct FakeImageCacheController: ImageCacheControllable {
    @MainActor init() {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = nil
    }
    
    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {}
    
    var imageCacheController: ImageCacheController
    var thumbnailCacheController: ImageCacheController
    var fileUrlDataController: FileUrlDataController?
}
