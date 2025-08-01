// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGPdfs
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGPdfs.PdfModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<PdfDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let bookmarks: [PdfBookmarkDataModel] = item.entries.enumerated().map { (index, entry) in
                PdfBookmarkDataModel(id: entry.id, index: Int16(index), name: entry.name, content: entry.content, bounds: JSONString.encode(value:  entry.bounds) ?? "", pageLabel: entry.pageLabel, parent: nil)
            }
            modelContext.insert(
                PdfDataModel(id: item.id, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, url: item.fileUrl?.rawUrl, bookmarks: bookmarks)
            )
        }
    }
}
