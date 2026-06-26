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
        PdfRoute.detail(itemId)
    }
    
    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        PdfDetailRoute.folder(itemId)
    }

    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        PdfDetailRoute.folderInline(itemId)
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId, nil)
    }

    func copy(listModel: FolderListModel) -> FolderListController {
        return FolderListController(
            listModel: listModel,
            listDisplayModel: listDisplayModel.newListDisplayModel,
            itemControllable: itemControllable,
            searchRootControllable: searchRootControllable.copy(listDisplayModel: listDisplayModel.newListDisplayModel))
    }
}
