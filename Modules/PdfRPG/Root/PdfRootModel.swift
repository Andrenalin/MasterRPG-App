// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class PdfRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let fileController = FileController()
        self.cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        self.editController = EditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.searchModel = SearchModel(modelContext: modelContext, module: PdfDataModel.typeId, categoryTags: [.adventure, .character, .rules, .supplement])
        
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

extension PdfRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = await itemController.item(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
    
    func loadImage(for itemId: UUID, isThumbnail: Bool) async -> AKImage? {
        isThumbnail ? await cacheController.thumbnail(for: itemId) : await cacheController.photo(for: itemId)
    }
}
