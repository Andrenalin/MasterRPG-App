// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGSpaces
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGSpaces.SpaceModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<SpaceDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                SpaceEntryDataModel(id: entry.id, index: Int16(index), parentId: item.id, spaceId: entry.spaceId, space: nil)
            }
            modelContext.insert(
                SpaceDataModel(id: item.id, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, url: item.fileUrl?.rawUrl, entries: entries)
            )
        }
    }
}
