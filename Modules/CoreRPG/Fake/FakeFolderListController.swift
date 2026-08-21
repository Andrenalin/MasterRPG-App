// @copyright André Trettin

import SwiftUI

@MainActor
struct FakeFolderListController: FolderListControllable {
    init(
        itemControllable: any ItemControllable = FakeItemController.fake,
        listModel: FolderListModel = FolderListModel(navigationModel: ModuleNavigationModel()),
        listDisplayModel: ListDisplayModel = ListDisplayModel(),
        searchModel: SearchModel = .preview(),
        searchRootControllable: any SearchRootControllable = FakeSearchController.fake,
        cacheListItemModel: CacheItemListModel = CacheItemListModel()
    ) {
        self.itemControllable = itemControllable
        self.listModel = listModel
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.searchRootControllable = searchRootControllable
        self.cacheListItemModel = cacheListItemModel
    }

    /// Satisfies `FolderListControllable`'s `init` requirement (added for the shared
    /// `copy(listModel:)` default — see CODE_AUDIT §9.4), which this fake doesn't otherwise
    /// need since it overrides `copy(listModel:)` itself below.
    init(listModel: FolderListModel, listDisplayModel: ListDisplayModel, itemControllable: any ItemControllable, searchRootControllable: any SearchRootControllable) {
        self.init(
            itemControllable: itemControllable,
            listModel: listModel,
            listDisplayModel: listDisplayModel,
            searchRootControllable: searchRootControllable
        )
    }

    func copy(listModel: FolderListModel) -> FakeFolderListController {
        FakeFolderListController()
    }
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }
    
    func folderDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }

    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }

    func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        InternalRoute.export(ids: [itemId])
    }
    
    let itemControllable: any ItemControllable
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let searchRootControllable: any SearchRootControllable
    let cacheListItemModel: CacheItemListModel


    static let fake = FakeFolderListController()
}
