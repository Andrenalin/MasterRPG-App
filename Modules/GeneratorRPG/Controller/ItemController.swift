// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.itemCacheModel = ItemCacheModel()
        self.container = container
        self.module = module
        self.modelCacheModel = ModelCacheModel()
    }
    let itemCacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
    let module: NetworkModules
    let modelCacheModel: ModelCacheModel<GeneratorDataModel>
}

extension ItemController: ModelCacheControllable {}

extension ItemController: ItemControllable {
    @MainActor func itemDataCodableModel(id: UUID) -> ItemDataCodableModel? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let ownModel = model(for: id)?.codableModel {
            externalData = try? encoder.encode(ownModel)
        }
        return itemDataCodableModel(for: id, externalData: externalData)
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        guard let model = itemDataCodableModel(id: id) else { return nil }
        let encoder = JSONEncoder()
        return try encoder.encode(model)
    }
}

// MARK: - Import Controller

extension ItemController: ImportDataControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        return try decoder.decode(ItemDataCodableModel.self, from: data)
    }

    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newTable = try? decoder.decode(GeneratorDataModel.GeneratorDataModelCodable.self, from: data) else { return }
        if let oldTable = model(for: id) {
            oldTable.replace(newTable)
        } else {
            let newModel = GeneratorDataModel(newTable)
            container.mainContext.insert(newModel)
        }
    }
}
