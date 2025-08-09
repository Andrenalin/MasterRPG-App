// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGDie
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGDie.DiceModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<DiceDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                DiceEntryDataModel(id: entry.id, index: index, parentId: item.id, childId: UUID(), item: nil)
            }
            modelContext.insert(
                DiceDataModel(id: item.id, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, entries: entries)
            )
        }
    }
}
