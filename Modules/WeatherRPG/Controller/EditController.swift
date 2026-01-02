// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class WeatherEditModel: Sendable {
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
}

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        self.editorModel = ItemEditorModel()
        self.weatherEditModel = WeatherEditModel()
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel
    let weatherEditModel: WeatherEditModel
}

extension EditController: EditControllable {
    typealias Model = WeatherModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.photoId = photoId
        save(updated: editModel, message: String(localized: "Change Photo").localizedString)
    }
}
