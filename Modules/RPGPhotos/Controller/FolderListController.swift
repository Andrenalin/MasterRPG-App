// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftData
import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    var parentModel: (any ItemDataAccessable)?
    
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let itemControllable: any ItemControllable
    let cacheListItemModel = CacheItemListModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        PhotoRoute.detail(itemId)
    }
    
    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        FolderListController(parentModel: parentModel, listModel: FolderListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel, itemControllable: itemControllable)
    }
}
