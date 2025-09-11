// @copyright André Trettin

import Foundation
import SwiftData

@Observable
public final class FakeItemRootController: ItemRootControllable {
    public init(itemController: any ItemControllable, module: NetworkModules) {
        modelContext = itemController.container.mainContext
        self.module = module

        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.cacheControllable = nil
        self.itemControllable = itemController

        let editController = FakeEditController(itemControllable: itemController, fileUrlDataController: nil)
        self.editControllable = editController
        let exportController = FakeExportController(itemControllable: itemController)
        self.exportControllable = exportController
        let linkController = FakeLinkController(itemController: FakeItemController(container: itemController.container))
        self.linkControllable = linkController
        let listController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listControllable = listController
        let listLinkController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        self.listLinkControllable = listController
        self.viewControllable = FakeViewController(goupViewType: .item, thumbnailRowViewType: .none)
        
        let rootController = ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportController,
            itemControllable: itemController,
            linkControllable: linkController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewControllable
        )
        self.rootController = rootController
    }
    
    public init(modelContext: ModelContext, module: NetworkModules) {
        self.modelContext = modelContext
        
        let module = module
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.cacheControllable = nil
        let itemController = FakeItemController(container: modelContext.container)
        self.itemControllable = itemController
        let editController = FakeEditController(itemControllable: itemController, fileUrlDataController: nil)
        self.editControllable = editController
        let exportController = FakeExportController(itemControllable: itemController)
        self.exportControllable = exportController
        let linkController = FakeLinkController(itemController: itemController)
        self.linkControllable = linkController
        let listController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listControllable = listController
        let listLinkController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        self.listLinkControllable = listController
        self.viewControllable = FakeViewController(goupViewType: .item, thumbnailRowViewType: .none)
        
        let rootController = ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportController,
            itemControllable: itemController,
            linkControllable: linkController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewControllable
        )
        self.rootController = rootController
    }

    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? = nil

    public let cacheControllable: (any ImageCacheControllable)?
    public let editControllable: any EditControllable
    public let exportControllable: any ExportControllable
    public let itemControllable: any ItemControllable
    public let linkControllable: any LinkControllable
    public let listControllable: any ListControllable
    public let listLinkControllable: any ListControllable
    public let viewControllable: any ViewControllable
    
    public var rootController: ItemRootController
}

extension LinkRootController {
    static var fake: LinkRootController = {
        let modelContainer = try! ModelContainer(for: ItemDataModel.self, LinkDataModel.self, TagDataModel.self, configurations: .init(isStoredInMemoryOnly: true))
        let fakeRoot = FakeItemRootController(
            modelContext: modelContainer.mainContext,
            module: .adventure
        )
        return LinkRootController(
            container: modelContainer,
            adventureRoot: fakeRoot,
            audioRoot: fakeRoot,
            characterRoot: fakeRoot,
            diceRoot: fakeRoot,
            mapRoot: fakeRoot,
            pdfRoot: fakeRoot,
            photoRoot: fakeRoot,
            spaceRoot: fakeRoot,
            tableRoot: fakeRoot,
            weatherRoot: fakeRoot
        )
    }()
}
