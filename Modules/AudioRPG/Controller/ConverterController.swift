// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGAudios
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGAudios.AudioModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                EntryDataModel(id: entry.id, index: index, parentId: item.id, childId: entry.audioId, item: nil)
            }
            modelContext.insert(
                ItemDataModel(id: item.id, module: .audio, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: item.fileUrl?.rawUrl, displayState: item.displayState, entries: entries)
            )
        }
    }
}
