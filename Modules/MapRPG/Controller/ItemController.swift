// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
}

// MARK: - Import Controller

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(MapModel.self, from: data)
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
        if let characterModel = model(for: id)?.codableModel {
            externalData = try encoder.encode(characterModel)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
        return try encoder.encode(model)
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newCharacter = try? decoder.decode(MapDataModel.MapDataModelCodable.self, from: data) else { return }
        if let oldCharacter = model(for: id) {
            oldCharacter.replace(newCharacter)
        } else {
            let newModel = MapDataModel(newCharacter)
            container.mainContext.insert(newModel)
        }
    }
}

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> MapDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<MapDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<MapDataModel>(predicate: predicate)
        let models: [MapDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let character = MapDataModel(itemId: itemId)
            container.mainContext.insert(character)
            try? container.mainContext.save()
            return character
        }
        return model
    }
}
