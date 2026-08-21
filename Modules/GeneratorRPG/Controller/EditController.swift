// @copyright André Trettin

import CoreRPG
import Foundation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.selectionReference = ItemSelectionModel()
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let selectionReference: ItemSelectionModel
}

// MARK: - EditControllable

extension EditController: EditControllable {
    typealias Model = GeneratorModel
    
    var itemControllable: any ItemControllable { itemController }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(referenceId: UUID?, model: GeneratorModel) {
        model.referenceId = referenceId
        save(
            updated: model,
            message: String(localized: "Reference added", bundle: .module)
        )
    }
}
