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
    var cacheModel: ItemCacheModel { get }
    var module: NetworkModules { get }
    
    var container: ModelContainer { get }
    var collectionCategory: ItemListCategory { get }
    
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel
    @MainActor func encodedItemData(for id: UUID) throws -> Data?
    func merge(with model: ItemDataCodableModel) async -> ItemDataCodableModel
    @MainActor func replace(model: ItemDataCodableModel?, isInsert: Bool, shouldRepairLinks: Bool)
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool)
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl?
}

public extension ItemControllable {
    @MainActor func update(items: [ItemDataModel]) async {
        let moduleItems = items.filter { $0.module == module }
        let ids = moduleItems.map {
            if cacheModel.cachedItems[$0.id] == nil {
                cacheModel.cachedItems[$0.id] = $0
            }
            return $0.id
        }
        if cacheModel.itemIds != ids {
            cacheModel.itemIds = ids
        }
    }
    
    @MainActor func allItemIds() -> [UUID] {
        cacheModel.itemIds
    }

    @MainActor func allItems() -> [ItemDataModel] {
        cacheModel.itemIds.compactMap { cacheModel.cachedItems[$0] }
    }

    @MainActor func item(for id: UUID) -> ItemDataModel? {
        cacheModel.cachedItems[id] //?? ItemDataModel.model(modelContext: ModelContext(container), id: id)
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
    
    @MainActor func itemDataCodableModel(for id: UUID, externalData: Data? = nil) -> ItemDataCodableModel? {
        guard let model = ItemDataModel.model(modelContext: ModelContext(container), id: id) else { return nil }
        
        let entries = model.entries.map { EntryDataCodableModel(id: $0.id, index: $0.index, parentId: $0.parentId, childId: $0.childId) }
        return ItemDataCodableModel(id: model.id, module: model.module, name: model._nameLWW, information: model._informationLWW, category: model.category, tags: model.tags, fileUrl: fileUrl(id: model.id, url: model.url), displayState: model.displayState, parentId: model.parentId, entries: entries, externalData: externalData)
    }

    func merge(with model: ItemDataCodableModel) async -> ItemDataCodableModel {
        model
    }

    @MainActor func replace(model: ItemDataCodableModel?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let model else { return }
        if let existingModel = item(for: model.id) {
            existingModel.replace(codableModel: model)
        } else {
            let entries = model.entries.map { EntryDataModel(id: $0.id, index: $0.index, parentId: $0.parentId, childId: $0.childId, item: nil)}
            let dataModel = ItemDataModel(id: model.id, module: model.module, name: model.name.wrappedValue, information: model.information.wrappedValue, category: model.category, tags: model.tags, url: model.fileUrl?.rawUrl, displayState: model.displayState, parentId: model.parentId, entries: entries)
            container.mainContext.insert(dataModel)
        }
        replace(id: model.id, data: model.externalData, isInsert: isInsert, shouldRepairLinks: shouldRepairLinks)
    }

    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {}

    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        return try decoder.decode(ItemDataCodableModel.self, from: data)
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        let model = itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
}
