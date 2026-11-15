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
    @MainActor init(itemController: ItemController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
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
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Change Photo", bundle: .module))
    }
    
    @MainActor func reset(cloudThickness: Cloud.Thickness, itemId: UUID) {
        reset(
            \.cloudThickness, value: cloudThickness, itemId: itemId,
            message: String(localized: "change cloud thickness", bundle: .module)
        )
    }

    @MainActor func reset(stormType: Storm.Contents, itemId: UUID) {
        reset(
            \.stormType, value: stormType, itemId: itemId,
            message: String(localized: "change storm type", bundle: .module)
        )
    }

    @MainActor func reset(time: Double, itemId: UUID) {
        reset(
            \.time, value: time, itemId: itemId,
            message: String(localized: "change time", bundle: .module)
        )
    }

    @MainActor func reset(rainIntensity: Double, itemId: UUID) {
        reset(
            \.rainIntensity, value: rainIntensity, itemId: itemId,
            message: String(localized: "change rain intensity", bundle: .module)
        )
    }

    @MainActor func reset(rainAngle: Double, itemId: UUID) {
        reset(
            \.rainAngle, value: rainAngle, itemId: itemId,
            message: String(localized: "change rain angle", bundle: .module)
        )
    }

    @MainActor func reset(lightningFrequency: Double, itemId: UUID) {
        reset(
            \.lightningFrequency, value: lightningFrequency, itemId: itemId,
            message: String(localized: "change lightning frequency", bundle: .module)
        )
    }

    @MainActor func reset(lightningMaxBolts: Double, itemId: UUID) {
        reset(
            \.lightningMaxBolts, value: lightningMaxBolts, itemId: itemId,
            message: String(localized: "change lightning max bolts", bundle: .module)
        )
    }

    @MainActor func reset(lightningForkProbability: Double, itemId: UUID) {
        reset(
            \.lightningForkProbability, value: lightningForkProbability, itemId: itemId,
            message: String(localized: "change lightning fork probability", bundle: .module)
        )
    }

    /// Shared body for the per-property `reset(...)` overloads above: each keeps its own literal
    /// `String(localized:)` call so String Catalog extraction still sees a static key per call site.
    @MainActor private func reset<Value: Equatable>(
        _ keyPath: WritableKeyPath<WeatherModel, Value>,
        value: Value,
        itemId: UUID,
        message: String
    ) {
        guard var item = editModel(for: itemId) else { return }
        item[keyPath: keyPath] <=> value
        save(updated: item, message: message)
    }
}
