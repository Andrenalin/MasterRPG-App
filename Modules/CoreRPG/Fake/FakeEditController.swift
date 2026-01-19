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
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), linkRegisterController: LinkRegisterController(root: nil), editorModel: ItemEditorModel(), cacheItemListModel: CacheItemListModel())
}
