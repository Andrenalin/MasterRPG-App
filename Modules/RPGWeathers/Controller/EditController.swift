// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class WeatherEditModel: Sendable {
    let photoSelectionModel = SelectionModel(id: UUID(), filter: .weather)
}

struct EditController: Sendable {
    @MainActor
    init(root: WeatherRoot, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.fileUrlDataController = nil
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
        self.weatherEditModel = WeatherEditModel()
    }

    weak var root: WeatherRoot!
    let fileUrlDataController: FileUrlDataController?
    let editorModel: ItemEditorModel
    let weatherEditModel: WeatherEditModel
}

extension EditController: EditControllable {
    typealias Model = WeatherModel
    
    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var rootControllable: any RootControllable {
        root.rootControllable
    }
    
    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId, weatherEditModel.photoSelectionModel.id != id else { return }
        weatherEditModel.photoSelectionModel.id = id
        if weatherEditModel.photoSelectionModel.currentValue != model.photoId {
            weatherEditModel.photoSelectionModel.currentValue = model.photoId
        }
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
