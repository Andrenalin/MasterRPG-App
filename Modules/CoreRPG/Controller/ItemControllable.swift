// @copyright André Trettin

import Foundation
import SwiftData

@MainActor @Observable
public final class ItemCacheModel {
    public init(itemIds: [UUID] = [], cachedItems: [UUID : ItemDataModel] = [:]) {
        self.itemIds = itemIds
        self.cachedItems = cachedItems
    }
    
    var itemIds: [UUID] = []
    
    @ObservationIgnored
    var cachedItems: [UUID: ItemDataModel] = [:]
}

public protocol ItemControllable: Sendable {
    var itemCacheModel: ItemCacheModel { get }
    var module: NetworkModules { get }
    
    var container: ModelContainer { get }
    var collectionCategory: ItemListCategory { get }
    
    @MainActor func itemVersion(for itemId: UUID) -> Int?
    @MainActor func encodedItemData(for id: UUID) throws -> Data?
    @MainActor func itemDataCodableModel(id: UUID) -> ItemDataCodableModel?
    @MainActor func itemDataCodableModel(for id: UUID, externalData: Data?) -> ItemDataCodableModel?
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl?
}

public extension ItemControllable {
    @MainActor func update(items: [ItemDataModel]) async {
        let moduleItems = items.filter { $0.module == module }
        let ids = moduleItems.map {
            if itemCacheModel.cachedItems[$0.id] == nil {
                print("\(module) not cached \($0.id)")
                itemCacheModel.cachedItems[$0.id] = $0
            }
            return $0.id
        }
        if itemCacheModel.itemIds != ids {
            print("\(module) item ids different")
            if itemCacheModel.itemIds.count == ids.count {
                for (index, itemId) in itemCacheModel.itemIds.enumerated() {
                    if ids[index] != itemId {
                        print("\(module) item ids not equal at index \(index) \(itemCacheModel.cachedItems[itemId]?.name ?? "not found")")
                    }
                }
            }
            itemCacheModel.itemIds = ids
        }
    }
    
    @MainActor func allItemIds() -> [UUID] {
        itemCacheModel.itemIds
    }
    
    @MainActor func allItems() -> [ItemDataModel] {
        itemCacheModel.itemIds.compactMap { itemCacheModel.cachedItems[$0] }
    }
    
    @MainActor func item(for id: UUID) -> ItemDataModel? {
        itemCacheModel.cachedItems[id] //?? ItemDataModel.model(modelContext: ModelContext(container), id: id)
    }
    
    @MainActor func item(for itemId: UUID, version: Int) -> Bool {
        version == itemVersion(for: itemId)
    }

    @MainActor func itemVersion(for itemId: UUID) -> Int? {
        itemCacheModel.cachedItems[itemId] != nil ? 0 : nil
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
        let fetchDesc = FetchDescriptor<ItemDataModel>(predicate: predicate)
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
    
    @MainActor func itemDataCodableModel(id: UUID) -> ItemDataCodableModel? {
        itemDataCodableModel(for: id, externalData: nil)
    }
    
    @MainActor func itemDataCodableModel(for id: UUID, externalData: Data? = nil) -> ItemDataCodableModel? {
        guard let model = item(for: id) else { return nil }
        let entries = model.entries.map { EntryDataCodableModel(id: $0.id, index: $0.index, parentId: $0.parentId, childId: $0.childId) }
        return ItemDataCodableModel(id: model.id, module: model.module, name: model._nameLWW, information: model._informationLWW, category: model.category, tags: model.tags, fileUrl: fileUrl(id: model.id, url: model.url), displayState: model.displayState, parentId: model.parentId, entries: entries, externalData: externalData)
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        let model = itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
}
