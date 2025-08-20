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
        
        let listModel = OldListModel()
        self.listModel = listModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = AudioRootModel.newSearchModel(modelContext: modelContext)
        self.searchModel = searchModel

        let fileController = FileController()
        self.audioController = AudioController(fileController: fileController, model: audioPlayerModel)
        self.editController = EditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = OldItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.listController = OldListController.listController(for: .main, modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkController = OldListController.listController(for: .link, modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)

        self.newItemController = ItemController(container: modelContext.container)

        self.newListController = ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)

        self._viewController = ViewController(_root: self)


        itemController.cleanDeleted()
    }
    
    public let modelContext: ModelContext

    public let module: NetworkModules = .audio
    public let listModel: OldListModel
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public let audioPlayerModel: AudioPlayerModel

    @ObservationIgnored let audioController: AudioController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: OldItemController
    @ObservationIgnored let listController: OldListController
    @ObservationIgnored let listLinkController: OldListController

    @ObservationIgnored let newListController: ListController
    @ObservationIgnored let newItemController: ItemController

    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    var currentSelectedItemId: UUID? {
        listModel.selectedItemId
    }
}

extension AudioRootModel: ItemRootControllable {
    public var editControllable: any OldEditControllable { editController }
    public var itemControllable: any ItemControllable { newItemController }
    public var listControllable: any ListControllable { newListController }
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
