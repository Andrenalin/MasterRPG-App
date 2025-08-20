// @copyright André Trettin

import Foundation
import SwiftData

public protocol ItemControllable: Sendable {
    var container: ModelContainer { get }
    var collectionCategory: ItemListCategory { get }
}

public extension ItemControllable {
    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<ItemDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func modelSync(for id: UUID) -> ItemDataModel? {
        ItemDataModel.model(modelContext: ModelContext(container), id: id)
    }
    
    func collections(isFolder: Bool, in parentId: UUID?) -> [ItemDataModel] {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<ItemDataModel> { $0.parentId == parentId && $0.displayState == 0 }
        let fetchDesc = FetchDescriptor<ItemDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.filter { $0.category == (isFolder ? .folder : collectionCategory) }
    }
    
    func cleanDeleted() {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<ItemDataModel> { $0.displayState == 2 }
        let fetchDesc = FetchDescriptor<ItemDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return }
        for model in models {
            modelContext.delete(model)
        }
    }

    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
