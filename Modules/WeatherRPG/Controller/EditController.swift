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
    @MainActor init(itemController: ItemController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.itemController = itemController
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        self.editorModel = ItemEditorModel()
        self.weatherEditModel = WeatherEditModel()
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let weatherEditModel: WeatherEditModel
}

extension EditController: EditControllable {
    typealias Model = WeatherModel
    
    var itemControllable: any ItemControllable { itemController }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Change Photo").localizedString)
    }
    
    @MainActor func reset(cloudThickness: Cloud.Thickness, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.cloudThickness <=> cloudThickness
        save(updated: item, message: String(localized: "change cloud thickness").localizedString)
    }
    
    @MainActor func reset(stormType: Storm.Contents, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.stormType <=> stormType
        save(updated: item, message: String(localized: "change storm type").localizedString)
    }
}
