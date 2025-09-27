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
    let modelCacheModel: ModelCacheModel<AdventureDataModel>
}

// MARK: - Import Controller

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(AdventureModel.self, from: data)
                return ConverterController.convert(old: oldModel, itemController: self)
            } catch {
                print(error)
                fatalError()
            }
        }
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
        guard let newCharacter = try? decoder.decode(AdventureDataModel.AdventureDataModelCodable.self, from: data) else { return }
        if let oldCharacter = model(for: id) {
            oldCharacter.replace(newCharacter)
        } else {
            let newModel = AdventureDataModel(newCharacter)
            container.mainContext.insert(newModel)
        }
    }
}

extension ItemController: ModelCacheControllable {}
