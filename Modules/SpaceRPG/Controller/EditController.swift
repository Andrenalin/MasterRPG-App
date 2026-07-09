// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = SpaceModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }
}
