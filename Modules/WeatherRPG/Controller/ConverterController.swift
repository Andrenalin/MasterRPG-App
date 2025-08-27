// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGWeathers
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGWeathers.WeatherModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .weather, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
    }
}
