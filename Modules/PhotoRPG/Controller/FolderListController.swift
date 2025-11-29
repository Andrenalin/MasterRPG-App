// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftData
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
        PhotoRoute.detail(itemId)
    }
    
    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        FolderListController(listModel: FolderListModel(parentModel: parentModel), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel, itemControllable: itemControllable)
    }
}
