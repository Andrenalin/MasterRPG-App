// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .diceBag
}

extension ItemController: ItemControllable {
    func encodedItemData(for id: UUID) async throws -> Data? {
        let encoder = JSONEncoder()
        let model = await itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
}

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> DiceConfigDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<DiceConfigDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<DiceConfigDataModel>(predicate: predicate)
        let models: [DiceConfigDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let config = DiceConfigDataModel(itemId: itemId)
            container.mainContext.insert(config)
            try? container.mainContext.save()
            return config
        }
        return model
    }
}
