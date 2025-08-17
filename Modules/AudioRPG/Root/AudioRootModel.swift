// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class AudioRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
        
        let listModel = ListModel()
        self.listModel = listModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = AudioRootModel.newSearchModel(modelContext: modelContext)
        self.searchModel = searchModel

        let fileController = FileController()
        self.audioController = AudioController(fileController: fileController, model: audioPlayerModel)
        self.editController = EditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.listController = ListController.listController(for: .main, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkController = ListController.listController(for: .link, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self._viewController = ViewController(_root: self)
        
        itemController.cleanDeleted()
    }
    
    let modelContext: ModelContext
    
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    public let audioPlayerModel: AudioPlayerModel

    @ObservationIgnored let audioController: AudioController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    var currentSelectedItemId: UUID? {
        listModel.selected
    }
}

extension AudioRootModel {
    static private func newSearchModel(modelContext: ModelContext) -> SearchModel {
        SearchModel(modelContext: modelContext, module: AudioDataModel.typeId, categoryTags: [.music, .sound])
    }
}

extension AudioRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = await itemController.item(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
}
