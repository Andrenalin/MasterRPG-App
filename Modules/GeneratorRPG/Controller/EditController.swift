// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.linkRegisterController = linkRegisterController
        self.itemController = itemController
        self.tagController = tagController
        self.editorModel = ItemEditorModel()
        self.sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        self.selectionReference = ItemSelectionModel()
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let sheetEditorModel: SheetEditorModel

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
        save(updated: model, message: "Reference added")
    }
}
