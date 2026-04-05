// @copyright André Trettin

import CoreRPG

import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let itemControllable: any ItemControllable
    let cacheListItemModel = CacheItemListModel()
    let detailInspectorModel = DetailInspectorModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        WeatherRoute.detail(itemId)
    }
    
    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        FolderListController(listModel: FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel, itemControllable: itemControllable)
    }
    
    func copy(listModel: FolderListModel) -> FolderListController {
        FolderListController(listModel: listModel, listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel, itemControllable: itemControllable)
    }
}
