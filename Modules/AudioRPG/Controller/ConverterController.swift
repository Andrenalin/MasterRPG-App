// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGPhotos
import SwiftData

public struct ConverterController {
    public static func insertPhotos(photos: [RPGPhotos.PhotoModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<AudioDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        photos.forEach { photo in
            guard let models, !models.contains(where: { $0.id == photo.id }) else { return }
            
            let entries = photo.entries.enumerated().map { (index, entry) in
                AudioEntryDataModel(id: entry.id, index: Int16(index), parentId: photo.id, itemId: entry.photoId, item: nil)
            }
            modelContext.insert(
                AudioDataModel(id: photo.id, name: photo.name, information: photo.description, category: CoreRPG.ItemListCategory(rawValue: photo.category.rawValue) ?? .adventure, tags: photo.tags, displayState: photo.displayState, degrees: photo.degrees, url: photo.fileUrl?.rawUrl, entries: entries)
            )
        }
    }
}
