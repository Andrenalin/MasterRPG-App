// @copyright André Trettin

import Foundation
import SwiftData

public struct TagController {
    public static func update(tags: Set<String>, in module: NetworkModules, modelContext: ModelContext) {
        let predicate = #Predicate<TagDataModel> { tag in
            tag.module == module.rawValue
        }
        let fetch = FetchDescriptor<TagDataModel>(predicate: predicate)
        guard let models = try? modelContext.fetch(fetch) else { return }
        let existingTags = Set(models.map(\.name))
        let missingTags = tags.subtracting(existingTags)
        missingTags.forEach {
            let model = TagDataModel(name: $0, module: module.rawValue)
            modelContext.insert(model)
        }
        
        let removedTags = existingTags.subtracting(tags)
        removedTags.forEach { tag in
            if let model = models.first(where: { $0.name == tag }) {
                modelContext.delete(model)
            }
        }
    }
}
