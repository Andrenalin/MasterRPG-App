// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI

struct EntryEditController {
    @MainActor init(editController: EditController) {
        self.editController = editController
        self.editorModel = EntryEditorModel()
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let editController: EditController
    let editorModel: EntryEditorModel
    let cacheItemListModel: CacheItemListModel
}

extension EntryEditController: EntryEditControllable {
    typealias EditDataModel = TableModel
    
    var editControllable: any EditControllable {
        editController
    }
}
