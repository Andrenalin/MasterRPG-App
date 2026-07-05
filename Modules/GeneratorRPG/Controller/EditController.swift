// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.itemController = itemController
        self.tagController = tagController
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
        self.selectionReference = ItemSelectionModel()
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let sheetRootModel: SheetRootModel
    let sheetEditorModel: SheetEditorModel

    let selectionReference: ItemSelectionModel
}

// MARK: - EditControllable

extension EditController: EditControllable {
    typealias Model = GeneratorModel
    
    var itemControllable: any ItemControllable { itemController }
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(referenceId: UUID?, model: GeneratorModel) {
        model.referenceId = referenceId
        save(updated: model, message: "Reference added")
    }
}
