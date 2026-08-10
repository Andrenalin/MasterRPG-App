// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {    
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let itemControllable: any ItemControllable
    let searchRootControllable: any SearchRootControllable
    let cacheListItemModel = CacheItemListModel()
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        TableRoute.detail(itemId)
    }

    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        TableDetailRoute.folder(itemId)
    }

    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        TableDetailRoute.folderInline(itemId)
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

    func copy(listModel: FolderListModel) -> FolderListController {
        let dependencies = copiedListDependencies
        return FolderListController(
            listModel: listModel,
            listDisplayModel: dependencies.listDisplayModel,
            itemControllable: itemControllable,
            searchRootControllable: dependencies.searchRootControllable)
    }
}
