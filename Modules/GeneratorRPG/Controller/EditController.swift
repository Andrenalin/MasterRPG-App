// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData

struct EditController {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
        self.selectionReference = ItemSelectionModel()
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel

    let selectionReference: ItemSelectionModel
}

// MARK: - EditControllable

extension EditController: EditControllable {
    typealias Model = GeneratorModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(referenceId: UUID?, model: GeneratorModel) {
        model.referenceId = referenceId
        save(with: "Reference added")
    }
}

