// @copyright André Trettin

import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct FakeImageCacheController: ImageCacheControllable {
    struct FileURLAccess: FileUrlAccessible {
        func fetchFileUrl() async -> [FileUrl] { [] }
        func saveFileUrl(fileUrl: FileUrl) async {}
        func fileUrl(item: any Observable) async -> FileUrl? { nil }
        func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {}
    }
    
    @MainActor init() {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        let fileUrlAccess = FileURLAccess()
        self.fileUrlAccess = fileUrlAccess
        self.fileUrlDataController = FileUrlDataController(moduleFolder: "Test", fileTypes: [.image], filenameExtension: ".jpg", fileUrlAccess: fileUrlAccess)
    }

    func createImage(for itemId: UUID, fileUrl: FileUrl?) async {
//        guard let image = AKImage(systemName: "gear") else { return }
//        await imageCacheController.setObject(image, for: itemId)
    }
    
    func createThumbnail(for itemId: UUID, fileUrl: FileUrl?) async {
//        guard let thumbnail = AKImage(systemName: "gear") else { return }
//        await thumbnailCacheController.setObject(thumbnail, for: itemId)
    }
    
    let fileUrlAccess: FileURLAccess
    
    var imageCacheController: ImageCacheController
    var thumbnailCacheController: ImageCacheController
    var fileUrlDataController: FileUrlDataController
}
