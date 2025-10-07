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
    let modelCacheModel: ModelCacheModel<CharacterDataModel>
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

// MARK: - Generable

extension ItemController {
    @MainActor func generable(id: UUID, level: Int = 0) -> CharacterDataModel.GenValue? {
        guard level < 10, let item = item(for: id), let cmodel = model(for: id) else { return nil }
        let entries = cmodel.entries.map {
            let groupdedValue: CharacterDataModel.GenValue?
            if let groupId = $0.valueId {
                groupdedValue = generable(id: groupId, level: level + 1)
            } else {
                groupdedValue = nil
            }
            return CharacterEntryDataModel.GenValue(name: $0.name, content: $0.content, valueType: $0.valueType, groupedValues: groupdedValue)
        }
        return CharacterDataModel.GenValue(name: item.name, information: item.information, tags: item.tags, entries: entries)
    }
}

// MARK: - Import Controller

extension ItemController: ImportDataControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(ValueModel.self, from: data)
                return ConverterController.convert(old: oldModel, itemController: self)
            } catch {
                print(error)
                fatalError()
            }
        }
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newCharacter = try? decoder.decode(CharacterDataModel.Value.self, from: data) else { return }
        if let oldCharacter = model(for: id) {
            oldCharacter.replace(newCharacter)
        } else {
            let newModel = CharacterDataModel(newCharacter)
            container.mainContext.insert(newModel)
        }
    }
}
