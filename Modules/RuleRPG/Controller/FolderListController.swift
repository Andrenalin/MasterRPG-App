// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let itemControllable: any ItemControllable
    let searchRootControllable: any SearchRootControllable
    let cacheListItemModel = CacheItemListModel()

    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        RuleRoute.detail(itemId)
    }

    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        RuleDetailRoute.folder(itemId)
    }

    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        RuleDetailRoute.folderInline(itemId)
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        RuleViewerRoute.viewer(itemId)
    }

}
