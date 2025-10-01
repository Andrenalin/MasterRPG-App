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
    
    @MainActor func decodedModel(codableModel: ItemDataCodableModel) throws -> DiceDataModel? {
        guard let externalData = codableModel.externalData else { return nil }
        let decoder = JSONDecoder()
        guard let diceDataModel = try? decoder.decode(DiceDataModel.DiceDataModelCodable.self, from: externalData) else { return nil }
        return DiceDataModel(diceDataModel)
    }

    @MainActor func decodedOldModel(codableModel: ItemDataCodableModel) throws -> DiceModel? {
        guard let externalData = codableModel.externalData else { return nil }
        let decoder = JSONDecoder()
        let diceDataModel = try? decoder.decode(DiceDataModel.DiceDataModelCodable.self, from: externalData)
        return DiceModel(id: codableModel.id, name: codableModel.name, description: codableModel.information, tags: CRDT<[String]>(wrappedValue: codableModel.tags), category: CRDT<ItemListCategory>(wrappedValue: codableModel.category), dice: CRDTDataUpdate<[DieModel]>(wrappedValue: []))
    }

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
