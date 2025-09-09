// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
}

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(WeatherModel.self, from: data)
                return ConverterController.convert(old: oldModel, container: container)
            } catch {
                print(error)
                fatalError()
            }
        }
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let weatherModel = model(for: id)?.codableModel {
            externalData = try encoder.encode(weatherModel)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
        return try encoder.encode(model)
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newWeather = try? decoder.decode(WeatherDataModel.WeatherDataModelCodable.self, from: data) else { return }
        if let oldWeather = model(for: id) {
            oldWeather.replace(newWeather)
        } else {
            let newModel = WeatherDataModel(newWeather)
            container.mainContext.insert(newModel)
        }
    }
}

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> WeatherDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<WeatherDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<WeatherDataModel>(predicate: predicate)
        let models: [WeatherDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let weather = WeatherDataModel(itemId: itemId)
            container.mainContext.insert(weather)
            try? container.mainContext.save()
            return weather
        }
        return model
    }
}
