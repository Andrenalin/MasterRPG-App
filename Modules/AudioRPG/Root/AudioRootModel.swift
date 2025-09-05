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
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
        
        itemController.cleanDeleted()
    }
    
    public let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
    
    @ObservationIgnored lazy var audioController: AudioController = {
        AudioController(fileController: fileController, model: audioPlayerModel)
    }()
    @ObservationIgnored lazy var editController: EditController = {
        EditController(itemControllable: itemController, fileUrlDataController: fileController.fileUrlDataController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(module: module, itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, gameExporter: false)
    }()
    @ObservationIgnored lazy var fileController: FileController = {
        FileController()
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, module: module)
    }()
    @ObservationIgnored lazy var itemController: ItemController = {
        ItemController(container: modelContext.container)
    }()
    @ObservationIgnored lazy var listController: ListController = {
        ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored lazy var listLinkController: ListController = {
        ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()
    @ObservationIgnored lazy var rootController: ItemRootController = {
        ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, itemSelectionModel: itemSelectionModel, cacheControllable: nil, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewController)
    }()
    
    public let audioPlayerModel: AudioPlayerModel
}

extension AudioRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var importControllable: any ImportControllable { importController }
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
