// @copyright André Trettin

import Foundation
import SwiftData

import CoreRPG
import CharacterRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG

@MainActor @Observable
public final class MapRootModel {
    init(modelContext: ModelContext, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) {
        self.modelContext = modelContext
        let module: NetworkModules = .map
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.building, .dungeon, .map])
        self.searchModel = searchModel
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        
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

    @ObservationIgnored let characterRoot: CharacterRootModel
    @ObservationIgnored let diceRoot: DiceRootModel
    @ObservationIgnored let pdfRoot: PdfRootModel
    @ObservationIgnored let photoRoot: PhotoRootModel
    @ObservationIgnored let tableRoot: TableRootModel

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
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            itemControllable: itemController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewController
        )
    }()
}

extension MapRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}
