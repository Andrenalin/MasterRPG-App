// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGValues
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGValues.ValueModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let character = CharacterRPG.CharacterDataModel(itemId: item.id, photoId: item.photoId, photos: item.photos, parentId: item.parentId)
            modelContext.insert(character)
            let entries = item.entries.enumerated().map { (index, entry) in
                CharacterEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.value, valueType: toCharacterValueType(entry.type), diceId: entry.diceId, valueId: entry.valueId)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .value, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .character, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
        
        try? modelContext.save()
    }
    
    static func toCharacterValueType(_ value: RPGValues.ValueEntryModel.ValueType) -> CharacterRPG.CharacterEntryDataModel.ValueType {
        CharacterRPG.CharacterEntryDataModel.ValueType(rawValue: value.rawValue) ?? .text
    }

    static func convert(old: CharacterRPG.ValueModel) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            CharacterEntryDataModel.CharacterEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: entry.value,
                valueType: entry.type,
                diceId: entry.diceId,
                valueId: entry.valueId
            )
        }
        let model = CharacterDataModel.CharacterDataModelCodable(
            itemId: old.id,
            diceId: entries.first { $0.diceId != nil }?.diceId,
            photoId: old.photoId.wrappedValue,
            photos: old.photos.wrappedValue,
            parentId: old.parentId,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)
        
        return ItemDataCodableModel(
            id: old.id,
            module: .value,
            name: old.name,
            information: old.description,
            category: old.category.wrappedValue,
            tags: old.tags.wrappedValue,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: old.parentId,
            entries: [],
            externalData: externalData
        )
    }
}
