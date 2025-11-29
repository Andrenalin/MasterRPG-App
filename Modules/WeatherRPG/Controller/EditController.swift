// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class WeatherEditModel: Sendable {
    let photoSelectionModel = SelectionModel(id: UUID(), filter: .weather)
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

    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId, weatherEditModel.photoSelectionModel.id != id else { return }
        weatherEditModel.photoSelectionModel.id = id
        if weatherEditModel.photoSelectionModel.currentValue != model.photoId {
            weatherEditModel.photoSelectionModel.currentValue = model.photoId
        }
    }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(photoId: UUID?) {
        model.photoId = photoId
        save(with: String(localized: "Change Photo").localizedString)
    }
}

extension EditController {
    @MainActor func selection(for module: NetworkModules) -> [ItemRowModel] {
        guard module == .photo else { return [] }
        if let id = model.photoId {
            return [ItemRowModel(itemId: id, typeId: .photo)]
        }
        return []
    }
    
    @MainActor func toggle(for module: NetworkModules, itemRowModel: ItemRowModel) async {
        guard module == .photo else { return }
        model.photoId = itemRowModel.itemId
        save(with: String(localized: "Change Photo").localizedString)
    }
}
