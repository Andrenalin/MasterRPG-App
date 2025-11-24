// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let itemControllable: any ItemControllable
    let cacheListItemModel = CacheItemListModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        WeatherRoute.detail(itemId)
    }
    
    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        FolderListController(listModel: FolderListModel(parentModel: parentModel), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel, itemControllable: itemControllable)
    }
}
