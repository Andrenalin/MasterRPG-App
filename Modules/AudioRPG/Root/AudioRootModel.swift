// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@MainActor @Observable
public final class AudioRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module: NetworkModules = .audio
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
        
        let fileController = FileController()
        let itemController = ItemController(container: modelContext.container)
        let editController = EditController(itemControllable: itemController, fileUrlDataController: fileController.fileUrlDataController)
        let listController = ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let listLinkController = ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let viewController = ViewController()

        self.audioController = AudioController(fileController: fileController, model: audioPlayerModel)
        self.editController = editController
        self.exportController = ExportController(module: module, itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.listController = listController
        self.listLinkController = listLinkController
        self.viewController = viewController
        self.rootController = ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, cacheControllable: nil, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewController)

        itemController.cleanDeleted()
    }
    
    public let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public let audioPlayerModel: AudioPlayerModel

    @ObservationIgnored let audioController: AudioController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored public let viewController: ViewController
    @ObservationIgnored let rootController: ItemRootController

    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
}

extension AudioRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension AudioRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = itemController.modelSync(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
}
