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
        cacheStorage = ImageCacheControllableStorage()
    }

    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {}

    let cacheStorage: ImageCacheControllableStorage
}
