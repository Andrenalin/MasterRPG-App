// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
}

extension ItemController: ItemControllable {
    func encodedItemData(for id: UUID) async throws -> Data? {
        let encoder = JSONEncoder()
        let model = await itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
}

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> TableDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<TableDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<TableDataModel>(predicate: predicate)
        let models: [TableDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let item = TableDataModel(itemId: itemId)
            container.mainContext.insert(item)
            try? container.mainContext.save()
            return item
        }
        return model
    }
}
