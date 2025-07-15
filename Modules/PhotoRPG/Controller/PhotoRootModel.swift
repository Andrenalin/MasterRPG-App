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
        self.editController = EditController(fileController: fileController)
    }

    let cacheController: CacheController
    let editController: EditController
    let fileController: FileController
    let networkModule: NetworkModules = .photo
}
