// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGAdventures
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGAdventures.AdventureModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }

            let entries = item.entries.enumerated().map { (index, entry) in
                AdventureEntryDataModel(
                    itemId: item.id,
                    entryId: entry.id,
                    index: index,
                    name: entry.name,
                    content: entry.content
                )
            }
            entries.forEach { modelContext.insert($0) }

            let character = AdventureRPG.AdventureDataModel(
                itemId: item.id,
                photoId: item.photoId,
                entries: entries,
            )
            modelContext.insert(character)
            
            modelContext.insert(
                ItemDataModel(
                    id: item.id,
                    module: .adventure,
                    name: item.name,
                    information: item.description,
                    category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .character,
                    tags: item.tags,
                    url: nil,
                    displayState: item.displayState
                )
            )
        }
        
        try? modelContext.save()
    }
    
    static func convert(old: AdventureRPG.AdventureModel) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            AdventureEntryDataModel.AdventureEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: entry.content
            )
        }
        let model = AdventureDataModel.AdventureDataModelCodable(
            itemId: old.id,
            photoId: old.photoId.wrappedValue,
            entries: entries,
        )
        let externalData = try? JSONEncoder().encode(model)
        
        return ItemDataCodableModel(
            id: old.id,
            module: .adventure,
            name: old.name,
            information: old.description,
            category: old.category.wrappedValue,
            tags: old.tags.wrappedValue,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}
