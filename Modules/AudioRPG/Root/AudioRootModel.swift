// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

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
        self.editController = OldEditController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = OldItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, fileController: fileController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.listController = OldListController.listController(for: .main, modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkController = OldListController.listController(for: .link, modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)

        let newItemController = ItemController(container: modelContext.container)
        self.newItemController = newItemController
        let newEditController = EditController(itemControllable: newItemController, fileUrlDataController: fileController.fileUrlDataController)
        self.newEditController = newEditController
        let newListController = ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.newListController = newListController
        let newListLinkController = ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.newListLinkController = newListLinkController

        self._viewController = ViewController(_root: self)
        self._rootController = ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, cacheControllable: nil, editControllable: newEditController, itemControllable: newItemController, listControllable: newListController, listLinkControllable: newListLinkController, viewControllable: viewControllable)


        itemController.cleanDeleted()
    }
    
    public let modelContext: ModelContext

    public let module: NetworkModules = .audio
    public let listModel: OldListModel
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public let audioPlayerModel: AudioPlayerModel

    @ObservationIgnored let audioController: AudioController
    @ObservationIgnored let editController: OldEditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: OldItemController
    @ObservationIgnored let listController: OldListController
    @ObservationIgnored let listLinkController: OldListController

    @ObservationIgnored let newEditController: EditController
    @ObservationIgnored let newItemController: ItemController
    @ObservationIgnored let newListController: ListController
    @ObservationIgnored let newListLinkController: ListController
    public var rootController: ItemRootController {
        _rootController.unsafelyUnwrapped
    }
    @ObservationIgnored private var _rootController: ItemRootController? = nil

    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    public var currentSelectedItemId: UUID? {
        listModel.selectedItemId
    }
}

extension AudioRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { newEditController }
    public var itemControllable: any ItemControllable { newItemController }
    public var listControllable: any ListControllable { newListController }
    public var listLinkControllable: any ListControllable { newListLinkController }
    public var viewControllable: any ViewControllable { viewController }
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
