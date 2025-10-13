// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?

    var rootControllable: any RootControllable

    var editorModel: ItemEditorModel
    
    var cacheItemListModel: CacheItemListModel
    
    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, rootControllable: FakeRootController.fake, editorModel: ItemEditorModel(), cacheItemListModel: CacheItemListModel())
}
