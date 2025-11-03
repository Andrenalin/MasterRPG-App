// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftData
import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let cacheListItemModel = CacheItemListModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        CharacterRoute.detail(itemId)
    }
    
    func copy() -> FolderListController {
        FolderListController(listModel: FolderListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
    }
}
