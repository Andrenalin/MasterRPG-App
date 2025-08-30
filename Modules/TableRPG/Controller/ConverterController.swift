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
            
            let table = TableRPG.TableDataModel(id: item.id, diceId: item.diceId)
            modelContext.insert(table)
            let entries = item.entries.enumerated().map { (index, entry) in
                TableEntryDataModel(parentId: item.id, id: entry.id, index: index, name: entry.name, content: entry.content)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .table, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .rules, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
    }
}
