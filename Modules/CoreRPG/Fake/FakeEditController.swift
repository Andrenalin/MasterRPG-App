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
    public static func previewFixture(
        root: any ItemRootControllable
    ) -> SheetRootModel {
        SheetRootModel(
            rootManager: root.rootManager ?? RootManager(anyRoot: root),
            linkControllable: root.linkControllable,
            sheetControllable: root.sheetControllable,
            sheetModel: .empty,
            isEditor: true
        )
    }

    /// Compatibility spelling that now returns an isolated graph per access.
    @MainActor
    public static var fake: SheetRootModel {
        let root = ItemRootController.previewFixture()
        return previewFixture(root: root)
    }
}
