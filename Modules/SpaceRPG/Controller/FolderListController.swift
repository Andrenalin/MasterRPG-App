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
        SpaceRoute.detail(itemId)
    }
    
    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        SpaceDetailRoute.folder(itemId)
    }
    
    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        SpaceDetailRoute.folderInline(itemId)
    }
    
    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

}
