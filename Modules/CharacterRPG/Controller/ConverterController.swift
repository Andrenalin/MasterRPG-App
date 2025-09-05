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
            
            let table = CharacterRPG.TableDataModel(itemId: item.id, diceId: nil)
            modelContext.insert(table)
            let entries = item.entries.enumerated().map { (index, entry) in
                TableEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.value)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .table, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .rules, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
        
        try? modelContext.save()
    }
    
    static func convert(old: TableModel) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            TableEntryDataModel.TableEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: entry.content
            )
        }
        let model = TableDataModel.TableDataModelCodable(
            itemId: old.id,
            diceId: old.diceId.wrappedValue,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)
        
        return ItemDataCodableModel(
            id: old.id,
            module: .table,
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
