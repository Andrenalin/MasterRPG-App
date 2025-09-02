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
        return try decoder.decode(ItemDataCodableModel.self, from: data)
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        let model = itemDataCodableModel(for: id)
        return try encoder.encode(model)
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
