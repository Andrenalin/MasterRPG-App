// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, tagController: TagController) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.tagController = tagController
        self.editorModel = ItemEditorModel()
        self.selectionReference = ItemSelectionModel()
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
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
        save(updated: model, message: "Reference added")
    }
}
