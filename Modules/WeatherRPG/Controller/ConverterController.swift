// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGWeathers
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGWeathers.WeatherModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let mappedThickness = toWeatherThickness(item.cloudThickness)
            let mappedStorm = toWeatherStorm(item.stormType)

            let model = WeatherDataModel(
                itemId: item.id,
                photoId: item.photoId,
                time: item.time,
                cloudThickness: mappedThickness,
                stormType: mappedStorm,
                rainAngle: item.rainAngle,
                rainIntensity: item.rainIntensity,
                lightningFrequency: item.lightningFrequency,
                lightningMaxBolts: item.lightningMaxBolts,
                lightningForkProbability: item.lightningForkProbability
            )
            modelContext.insert(model)
            
            modelContext.insert(
                ItemDataModel(
                    id: item.id,
                    module: .weather,
                    name: item.name,
                    information: item.description,
                    category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure,
                    tags: item.tags,
                    url: nil,
                    displayState: item.displayState
                )
            )
        }
        try? modelContext.save()
    }
    
    static func convert(old: WeatherModel) -> ItemDataCodableModel {
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

        return ItemDataCodableModel(
            id: old.id,
            module: .weather,
            name: old.name,
            information: old.description,
            category: old.category.wrappedValue,
            tags: old.tags.wrappedValue,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}

private extension ConverterController {
    static func toWeatherThickness(_ value: RPGWeathers.Cloud.Thickness) -> WeatherRPG.Cloud.Thickness {
        WeatherRPG.Cloud.Thickness(rawValue: value.rawValue) ?? .none
    }

    static func toWeatherStorm(_ value: RPGWeathers.Storm.Contents) -> WeatherRPG.Storm.Contents {
        WeatherRPG.Storm.Contents(rawValue: value.rawValue) ?? .none
    }
}
