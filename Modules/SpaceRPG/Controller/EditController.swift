// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController, linkController: LinkController, sheetController: SheetController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        self.sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: sheetEditorModel
        )
        self.sheetEditorModel = sheetEditorModel
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let sheetRootModel: SheetRootModel
    let sheetEditorModel: SheetEditorModel
}

extension EditController: EditControllable {
    typealias Model = SpaceModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
}
