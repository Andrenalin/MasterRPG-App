// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGPhotos
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGPhotos.PhotoModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                PhotoEntryDataModel(id: entry.id, index: Int16(index), parentId: item.id, itemId: entry.photoId, item: nil)
            }
            modelContext.insert(
                PhotoDataModel(id: item.id, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, url: item.fileUrl?.rawUrl, entries: entries, degrees: item.degrees)
            )
        }
    }
}
