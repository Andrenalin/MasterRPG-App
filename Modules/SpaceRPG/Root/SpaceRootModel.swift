// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class SpaceRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let fileController = FileController()
        self.cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        self.editController = EditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.searchModel = SpaceRootModel.newSearchModel(modelContext: modelContext)
        
        self._viewController = ViewController(_root: self)

        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    @ObservationIgnored let cacheController: CacheController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }

    let listModel = ListModel()
    let listDisplayModel = ListDisplayModel()
    let searchModel: SearchModel
    var currentSelectedItemId: UUID? {
        listModel.selected
    }
}

extension SpaceRootModel {
    func newSearchModel() -> SearchModel {
        Self.newSearchModel(modelContext: modelContext)
    }
    
    static private func newSearchModel(modelContext: ModelContext) -> SearchModel {
        SearchModel(modelContext: modelContext, module: SpaceDataModel.typeId, categoryTags: [.building, .item, .supplement])
    }
}

extension SpaceRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = await itemController.item(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
    
    func loadImage(for itemId: UUID, isThumbnail: Bool) async -> AKImage? {
        isThumbnail ? await cacheController.thumbnail(for: itemId) : await cacheController.photo(for: itemId)
    }
}
