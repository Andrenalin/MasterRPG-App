// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class SpaceRootModel {
    init(modelContext: ModelContext) {
        let fileController = FileController()
        self.cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        self.editController = EditController(fileController: fileController)
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
    }

    @ObservationIgnored let cacheController: CacheController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: ItemController
    
    @ObservationIgnored let networkModule: NetworkModules = .space
}


extension SpaceRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = await itemController.item(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
}
