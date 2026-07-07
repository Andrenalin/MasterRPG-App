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
    @MainActor init(rootManager: RootManager, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        let sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: sheetEditorModel
        )
        editorModel.sheetRootModel = sheetRootModel
        self.weatherEditModel = WeatherEditModel()
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let weatherEditModel: WeatherEditModel
}

extension EditController: EditControllable {
    typealias Model = WeatherModel
    
    var itemControllable: any ItemControllable { itemController }
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Change Photo", bundle: .module).localizedString)
    }
    
    @MainActor func reset(cloudThickness: Cloud.Thickness, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.cloudThickness <=> cloudThickness
        save(updated: item, message: String(localized: "change cloud thickness", bundle: .module).localizedString)
    }
    
    @MainActor func reset(stormType: Storm.Contents, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.stormType <=> stormType
        save(updated: item, message: String(localized: "change storm type", bundle: .module).localizedString)
    }
    
    @MainActor func reset(lightningFrequency: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.lightningFrequency <=> lightningFrequency
        save(updated: item, message: String(localized: "change lightning frequency", bundle: .module).localizedString)
    }

    @MainActor func reset(lightningMaxBolts: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.lightningMaxBolts <=> lightningMaxBolts
        save(updated: item, message: String(localized: "change lightning max bolts", bundle: .module).localizedString)
    }
    
    @MainActor func reset(lightningForkProbability: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.lightningForkProbability <=> lightningForkProbability
        save(updated: item, message: String(localized: "change lightning fork probability", bundle: .module).localizedString)
    }
}
