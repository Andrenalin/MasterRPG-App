// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?
    var tagController: TagController
    var linkRegisterController: LinkRegisterController

    var editorModel: ItemEditorModel
    var sheetEditorModel: SheetEditorModel

    var cacheItemListModel: CacheItemListModel

    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), linkRegisterController: LinkRegisterController(root: nil), editorModel: ItemEditorModel(), sheetEditorModel: SheetEditorModel(), cacheItemListModel: CacheItemListModel())
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
    
    func merge(itemId: UUID, entries: [FakeEntryModel], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
        []
    }
}
