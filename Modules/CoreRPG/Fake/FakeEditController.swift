// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    var linkRegisterControllable: any LinkRegisterControllable {
        rootControllable.linkRegisterControllable
    }
        
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?
    var tagController: TagController

    var rootControllable: any RootControllable

    var editorModel: ItemEditorModel
    
    var cacheItemListModel: CacheItemListModel
    
    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), rootControllable: FakeRootController.fake, editorModel: ItemEditorModel(), cacheItemListModel: CacheItemListModel())
}
