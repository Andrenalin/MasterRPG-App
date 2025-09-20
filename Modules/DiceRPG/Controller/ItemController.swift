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
    let collectionCategory: ItemListCategory = .diceBag
    let module: NetworkModules
    let modelCacheModel: ModelCacheModel<DiceDataModel>
}

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            let oldModel = try decoder.decode(DiceModel.self, from: data)
            return ConverterController.convert(old: oldModel)
        }
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let diceModel = model(for: id)?.codableModel {
            externalData = try encoder.encode(diceModel)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
        return try encoder.encode(model)
    }

    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newDice = try? decoder.decode(DiceDataModel.DiceDataModelCodable.self, from: data) else { return }
        if let oldDice = model(for: id) {
            oldDice.replace(newDice)
        } else {
            let newModel = DiceDataModel(newDice)
            container.mainContext.insert(newModel)
        }
    }
}

extension ItemController: ModelCacheControllable {}
