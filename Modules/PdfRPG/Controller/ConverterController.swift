// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGPdfs
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGPdfs.PdfModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            item.entries.enumerated().forEach { (index, entry) in
                let bookmark = PdfDataModel(id: entry.id, itemId: item.id, index: index, name: entry.name, content: entry.content, bounds: entry.bounds, pageLabel: entry.pageLabel)
                modelContext.insert(bookmark)
            }
            modelContext.insert(
                ItemDataModel(id: item.id, module: .pdf, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: item.fileUrl?.rawUrl, displayState: item.displayState)
            )
        }
    }
}
