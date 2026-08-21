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
        AdventureRoute.detail(itemId)
    }

    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        AdventureDetailRoute.folder(itemId)
    }

    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        AdventureDetailRoute.folderInline(itemId)
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

}
