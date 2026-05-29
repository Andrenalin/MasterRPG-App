// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let itemControllable: any ItemControllable
    let searchRootControllable: any SearchRootControllable
    let cacheListItemModel = CacheItemListModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        AdventureRoute.detail(itemId)
    }
    
    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        let newSearchModel = searchRootControllable.searchModel.newSearchModel
        return FolderListController(
            listModel: FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel),
            listDisplayModel: listDisplayModel.newListDisplayModel,
            itemControllable: itemControllable,
            searchRootControllable: searchRootControllable)
    }

    func copy(listModel: FolderListModel) -> FolderListController {
        let newSearchModel = searchRootControllable.searchModel.newSearchModel
        return FolderListController(
            listModel: listModel,
            listDisplayModel: listDisplayModel.newListDisplayModel,
            itemControllable: itemControllable,
            searchRootControllable: searchRootControllable)
    }
}
