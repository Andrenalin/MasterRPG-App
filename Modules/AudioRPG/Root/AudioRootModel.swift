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
        let fileController = FileController()
        self.audioController = AudioController(fileController: fileController, model: audioPlayerModel)
        self.editController = EditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.searchModel = AudioRootModel.newSearchModel(modelContext: modelContext)
        
        self._viewController = ViewController(_root: self)

        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    @ObservationIgnored let audioController: AudioController
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
    
    public let audioPlayerModel: AudioPlayerModel
    
    func newSearchModel() -> SearchModel {
        Self.newSearchModel(modelContext: modelContext)
    }
    
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
