// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGTables
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGTables.TableModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let table = TableRPG.TableDataModel(itemId: item.id, diceId: item.diceId)
            modelContext.insert(table)
            let entries = item.entries.enumerated().map { (index, entry) in
                TableEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.content)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .table, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .rules, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
        
        try? modelContext.save()
    }
    
    static func convert(old: TableModel, container: ModelContainer) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            let updatedContent = scanAndRegisterLinks(in: entry.content, destinationId: old.id, destinationEntryId: entry.id, destinationModule: .table, container: container)
            TableEntryDataModel.TableEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: updatedContent
            )
        }
        let model = TableDataModel.TableDataModelCodable(
            itemId: old.id,
            diceId: old.diceId.wrappedValue,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)
        
        // Register diceId as a link if present
        if let diceId = old.diceId.wrappedValue {
            let linkRegisterController = LinkRegisterController(container: container)
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .table, destinationId: diceId, destinationModule: .dice)
        }
        
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
    
    static func scanAndRegisterLinks(in text: String, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules, container: ModelContainer) -> String {
        let linkReplaceModels = LinkReplaceController.links(for: text)
        let linkRegisterController = LinkRegisterController(container: container)
        
        var updatedText = text
        
        for link in linkReplaceModels {
            let linkId = linkRegisterController.register(link: link, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModule: destinationModule)
            let newLinkFormat = "[\(link.name)](RPG://\(linkId.uuidString))"
            updatedText = updatedText.replacingOccurrences(of: link.markDown, with: newLinkFormat)
        }
        
        return updatedText
    }
}
