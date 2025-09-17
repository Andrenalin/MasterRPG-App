// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class DiceRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module: NetworkModules = .dice
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.rules, .table, .value])
        self.searchModel = searchModel

        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
    public let removeEntryListModel = RemoveEntryListModel()

    @ObservationIgnored lazy var editController: EditController = {
        EditController(itemControllable: itemController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(module: module, itemController: itemController, gameExporter: false)
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, module: module)
    }()
    @ObservationIgnored lazy var itemController: ItemController = {
        ItemController(container: modelContext.container)
    }()
    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(module: module, itemController: itemController)
    }()
    @ObservationIgnored lazy var listController: ListController = {
        ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored lazy var listLinkController: ListController = {
        ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()
    @ObservationIgnored lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            itemControllable: itemController,
            linkControllable: linkController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewController
        )
    }()
}

extension DiceRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var linkControllable: any LinkControllable { linkController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}
