// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?
    var tagController: TagController
    var linkRegisterController: LinkRegisterController

    var editorModel: ItemEditorModel
    var sheetRootModel: SheetRootModel
    var sheetEditorModel: SheetEditorModel

    var cacheItemListModel: CacheItemListModel

    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), linkRegisterController: LinkRegisterController(root: nil), editorModel: ItemEditorModel(), sheetRootModel: SheetRootModel.fake, sheetEditorModel: SheetEditorModel(), cacheItemListModel: CacheItemListModel())
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
    static let fake: SheetRootModel = SheetRootModel(rootManager: RootManager.preview(fake: ItemRootController.fake), linkControllable: FakeLinkController.fake, sheetControllable: FakeSheetController.fake, sheetModel: .empty, isEditor: true)
}
