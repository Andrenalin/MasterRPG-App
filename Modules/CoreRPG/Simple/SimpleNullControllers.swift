// @copyright André Trettin

import Foundation
import SwiftUI

// The peripheral controllables a `SimpleSheetEditingSession` needs only to fill the slots of its
// `ItemRootController`. A pure add/edit-entries session never exports, imports, searches or
// browses folders, so these do nothing — but unlike the preview `Fake*` doubles they are
// production types: every session gets its own instances (no state shared between two open
// editors), they use the session's own item and edit controllers, and none of them traps.
// See CODE_AUDIT_26 §9.3.

/// Export that has nothing to export. Its hub is a stateless value, so reading
/// `rootExportController`/`rootImportController` is safe at any time.
struct SimpleNullExportController: ExportControllable {
    let itemControllable: any ItemControllable
    let editControllable: any EditControllable

    var hubControllable: any RootExportControllable {
        SimpleNullExportHub(
            exportControllable: self,
            importControllable: SimpleNullImportController(itemControllable: itemControllable, editControllable: editControllable)
        )
    }
}

struct SimpleNullExportHub: RootExportControllable {
    let exportControllable: any ExportControllable
    let importControllable: any ImportControllable
}

struct SimpleNullImportController: ImportControllable {
    let itemControllable: any ItemControllable
    let editControllable: any EditControllable
}

struct SimpleNullGameController: GameControllable {
    let itemControllable: any ItemControllable
    let exportControllable: any ExportControllable
    let importControllable: any ImportControllable
    let gameModel: ItemGameModel
}

struct SimpleNullViewController: ViewControllable {
    var thumbnailRowViewType: ThumbnailRowViewType = .none
    var sharingViewType: SharingViewType = .none
}

@MainActor
struct SimpleNullSearchController: SearchControllable, SearchRootControllable {
    let itemControllable: any ItemControllable
    let searchModel: SearchModel

    init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
        self.searchModel = SearchModel(tagController: TagController(), module: itemControllable.config.module)
    }

    func results(text: String) async -> [SearchResult] { [] }
    func scopedResults(text: String, focusId: UUID) async -> [SearchResult] { [] }
    func syncExpandResults(focusId: UUID) -> [SearchResult] { [] }

    func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable { self }
}

@MainActor
struct SimpleNullFolderListController: FolderListControllable {
    let itemControllable: any ItemControllable
    let listModel: FolderListModel
    let listDisplayModel: ListDisplayModel
    let searchRootControllable: any SearchRootControllable
    let cacheListItemModel = CacheItemListModel()

    init(listModel: FolderListModel, listDisplayModel: ListDisplayModel, itemControllable: any ItemControllable, searchRootControllable: any SearchRootControllable) {
        self.listModel = listModel
        self.listDisplayModel = listDisplayModel
        self.itemControllable = itemControllable
        self.searchRootControllable = searchRootControllable
    }

    init(itemControllable: any ItemControllable, searchRootControllable: any SearchRootControllable) {
        self.init(
            listModel: FolderListModel(navigationModel: ModuleNavigationModel()),
            listDisplayModel: ListDisplayModel(),
            itemControllable: itemControllable,
            searchRootControllable: searchRootControllable
        )
    }

    func detailDestination(for itemId: UUID) -> any NavigationDestination { InternalRoute.export(ids: [itemId]) }
    func folderDestination(for itemId: UUID) -> any NavigationDestination { InternalRoute.export(ids: [itemId]) }
    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination { InternalRoute.export(ids: [itemId]) }
    func viewerDestination(for itemId: UUID) -> any NavigationDestination { InternalRoute.export(ids: [itemId]) }
}
