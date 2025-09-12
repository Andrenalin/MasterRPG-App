// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    @MainActor static func convert(old: WeatherModel, itemController: ItemController) -> ItemDataCodableModel {
        let model = WeatherDataModel.WeatherDataModelCodable(
            itemId: old.id,
            photoId: old.photoId,
            time: old.time,
            cloudThickness: old.cloudThickness,
            stormType: old.stormType,
            rainAngle: old.rainAngle,
            rainIntensity: old.rainIntensity,
            lightningFrequency: old.lightningFrequency,
            lightningMaxBolts: old.lightningMaxBolts,
            lightningForkProbability: old.lightningForkProbability
        )
        let externalData = try? JSONEncoder().encode(model)

        // Register photoId as a link if present
        if let photoId = old.photoId {
            let linkController = LinkRegisterController(container: itemController.container)
            _ = linkController.register(sourceId: old.id, sourceModule: .weather, destinationId: photoId, destinationModule: .photo)
        }

        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .weather, collection: .collection)
        return ItemDataCodableModel(
            id: old.id,
            module: .weather,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}
