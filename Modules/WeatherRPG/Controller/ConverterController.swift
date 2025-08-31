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
}

private extension ConverterController {
    static func toWeatherThickness(_ value: RPGWeathers.Cloud.Thickness) -> WeatherRPG.Cloud.Thickness {
        WeatherRPG.Cloud.Thickness(rawValue: value.rawValue) ?? .none
    }

    static func toWeatherStorm(_ value: RPGWeathers.Storm.Contents) -> WeatherRPG.Storm.Contents {
        WeatherRPG.Storm.Contents(rawValue: value.rawValue) ?? .none
    }
}
