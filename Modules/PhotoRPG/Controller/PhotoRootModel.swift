// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class PhotoRootModel {
    init() {
        let fileController = FileController()
        self.cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        self.fileController = fileController
    }

    let cacheController: CacheController
    let fileController: FileController
    let networkModule: NetworkModules = .photo
}
