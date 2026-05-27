// @copyright André Trettin

import CoreRPG

import SwiftUI

@MainActor
struct FolderListController: FolderListControllable {
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let itemControllable: any ItemControllable
    let itemController: ItemController
    let cacheListItemModel = CacheItemListModel()

    /// When a character is selected as the parent model, use the inspector-scoped search
    /// that follows `ValueEntryModel.valueId` links through the character's value tree.
    /// Falls back to the module-wide `SearchController` when no parent is active.
    var searchControllable: any SearchControllable {
        if let parentId = listModel.parentItemId {
            return InspectorSearchController(itemController: itemController, characterId: parentId)
        }
        return SearchController(itemController: itemController)
    }

    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        CharacterRoute.detail(itemId)
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }

    func copy(parentModel: (any ItemDataAccessable)?) -> FolderListController {
        FolderListController(
            listModel: FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel),
            listDisplayModel: listDisplayModel.newListDisplayModel,
            searchModel: searchModel.newSearchModel,
            itemControllable: itemControllable,
            itemController: itemController
        )
    }

    func copy(listModel: FolderListModel) -> FolderListController {
        FolderListController(
            listModel: listModel,
            listDisplayModel: listDisplayModel.newListDisplayModel,
            searchModel: searchModel.newSearchModel,
            itemControllable: itemControllable,
            itemController: itemController
        )
    }
}
