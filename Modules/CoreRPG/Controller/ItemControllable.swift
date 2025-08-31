// @copyright André Trettin

import Foundation
import SwiftData

public protocol ItemControllable: Sendable {
    var container: ModelContainer { get }
    var collectionCategory: ItemListCategory { get }
    
    @MainActor func encodedItemData(for id: UUID) throws -> Data?
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl?
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
        let url = await actor.url
        return await fileUrl(id: id, url: url)
    }
    
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? { nil }
    
    @MainActor func itemDataCodableModel(for id: UUID) -> ItemDataCodableModel? {
        guard let model = ItemDataModel.model(modelContext: ModelContext(container), id: id) else { return nil }
        
        let entries = model.entries.map { EntryDataCodableModel(id: $0.id, index: $0.index, parentId: $0.parentId, childId: $0.childId) }
        return ItemDataCodableModel(id: model.id, module: model.module, name: model._nameLWW, information: model._informationLWW, category: model.category, tags: model.tags, fileUrl: fileUrl(id: model.id, url: model.url), displayState: model.displayState, parentId: model.parentId, entries: entries)
    }
}
