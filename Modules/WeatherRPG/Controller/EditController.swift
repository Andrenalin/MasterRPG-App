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
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
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
    @MainActor func add(photoId: UUID?) {
        model.photoId = photoId
        save(with: String(localized: "Change Photo").localizedString)
    }
}
