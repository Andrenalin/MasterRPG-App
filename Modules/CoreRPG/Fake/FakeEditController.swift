// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?
    var tagController: TagController
    var linkRegisterController: LinkRegisterController

    var editorModel: ItemEditorModel

    var cacheItemListModel: CacheItemListModel

    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), linkRegisterController: LinkRegisterController(root: nil), editorModel: ItemEditorModel(sheetEditorModel: SheetEditorModel()), cacheItemListModel: CacheItemListModel())
}

extension FakeEditController: EntryDataEditable {
    var linkModules: [NetworkModules] {
        []
    }
    
    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }
    
    func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }
    
    func create(name: String, content: String) -> FakeEntryModel {
        FakeEntryModel.empty
    }

    func merge(itemId: UUID, entries: [FakeEntryModel]) -> [FakeEntryModel] {
        entries
    }
    
    func merge(itemId: UUID, entries: [FakeEntryModel], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
        []
    }
}

extension SheetRootModel {
    @MainActor
    static let fake: SheetRootModel = SheetRootModel(
        rootManager: RootManager(anyRoot: FakeSheetItemRoot()),
        linkControllable: FakeLinkController.fake,
        sheetControllable: FakeSheetController.fake,
        sheetModel: .empty,
        isEditor: true
    )
}

// Breaks the static fake cycle: ItemRootController.fake -> FakeEditController.fake -> SheetRootModel.fake.
private struct FakeSheetItemRoot: ItemRootControllable {
    var rootManager: RootManager { RootManager(anyRoot: self) }
    var configurable: ModuleConfigurable { FakeModuleConfiguration() }
    var navigationModel: ModuleNavigationModel { ModuleNavigationModel() }
    var inspectorEditorLinkModel: EditorLinkModel? { nil }
    var openFileWindowModel: OpenFileWindowModel { OpenFileWindowModel() }
    var currentSelectedItemId: UUID? { nil }
    var itemSelectionModel: ItemSelectionModel { ItemSelectionModel() }
    var removeEntryListModel: RemoveEntryListModel { RemoveEntryListModel() }
    var cacheControllable: (any ImageCacheControllable)? { nil }
    var editControllable: any EditControllable { FakeEditController.fake }
    var exportControllable: any ExportControllable { FakeExportController.fake }
    var gameControllable: any GameControllable { FakeGameController.fake }
    var importControllable: any ImportControllable { FakeImportController.fake }
    var itemControllable: any ItemControllable { FakeItemController.fake }
    var linkControllable: any LinkControllable { FakeLinkController.fake }
    var folderListControllable: any FolderListControllable { FakeFolderListController.fake }
    var folderLinkControllable: any FolderListControllable { FakeFolderListController.fake }
    var searchControllable: any SearchControllable { FakeSearchController.fake }
    var sheetControllable: any SheetControllable { FakeSheetController.fake }
    var viewControllable: any ViewControllable { FakeViewController() }
    var rootController: ItemRootController { ItemRootController.fake }
}
