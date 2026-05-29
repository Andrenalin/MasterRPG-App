// @copyright André Trettin

import SwiftUI

@MainActor
struct FakeFolderListController: FolderListControllable {
    
    func copy(parentModel: (any ItemDataAccessable)?) -> FakeFolderListController {
        FakeFolderListController()
    }
    
    func copy(listModel: FolderListModel) -> FakeFolderListController {
        FakeFolderListController()
    }
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }
    
    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }
    
    let itemControllable: any ItemControllable = FakeItemController.fake
    let listModel: FolderListModel = FolderListModel(navigationModel: ModuleNavigationModel())
    let listDisplayModel: ListDisplayModel = ListDisplayModel()
    let searchModel: SearchModel = .preview()
    let searchRootControllable: any SearchRootControllable = FakeSearchController.fake
    let cacheListItemModel = CacheItemListModel()


    static let fake = FakeFolderListController()
}
