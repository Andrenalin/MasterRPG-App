// @copyright André Trettin

import Foundation
import Observation

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistable & Identifiable & Equatable & Hashable & Codable & ModelType
    
    var cacheControllable: ImageCacheControllable? { get }
    var config: ModuleConfigurable { get }
    var collectionCategory: ItemListCategory { get }
    var dataControllable: (any DataPersistenceControllable)? { get }
    var fileUrlDataController: FileUrlDataController? { get }
    
    @MainActor var linkRegisterController: LinkRegisterController { get }
    var itemDataModel: ItemDataModel { get }
    
    @MainActor func children(itemId: UUID) -> [Model]
    @MainActor func subChildren(itemId: UUID, entryId: UUID?) -> [Model]
}

// MARK: - Configuration

public extension ItemControllable {
    var cacheControllable: ImageCacheControllable? { nil }
    var collectionCategory: ItemListCategory { .collection }
    var fileUrlDataController: FileUrlDataController? { nil }
}

// MARK: - ContextMenuMultiController

public extension ItemControllable {
    @MainActor func collections(isFolder: Bool, in parentId: UUID?) -> [Model] {
        return itemDataModel.items.compactMap { itemId -> Model? in
            guard let item = itemSync(for: itemId),
                  item.displayState == 0 && item.parentId == parentId && (item.category == (isFolder ? .folder : collectionCategory)) else { return nil }
            return item
        }
    }
}

// MARK: - EditControllable

public extension ItemControllable {
    @MainActor func addNew(type: ItemListCategory) async -> UUID {
        var model = Model.empty.copy()
        model.category = type
        try? await dataControllable?.replace(id: model.id, with: model)
        insertIntoItems(model: model)
        setModel(with: model)
        await save()
        return model.id
    }

    @MainActor func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }
    
    func delete(itemId: UUID, withFileData: Bool = true) async {
        guard let item = await self.item(for: itemId) else { return }
        let entries = item.entries
        for entry in entries {
            await cacheControllable?.remove(itemId: entry.id)
        }
        
        try? await dataControllable?.delete(id: item.id)
        if let fileUrlDataController, let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            if withFileData {
                fileUrlDataController.delete(fileUrl)
            }
        }
        
        await itemDataModel.resetModel(id: item.id)
    }
    
    @MainActor func isEqual(with other: ModelType) -> Bool {
        guard let other = other as? Model, let second = self.itemSync(for: other.id) else { return false }
        return second.isEqual(other: other)
    }
    @MainActor func replace(model: ModelType?, isInsert: Bool, forceSave: Bool = false) {
        guard let model = model as? Model else { return }
        if itemDataModel.isGameMode == true && forceSave == false {
            itemDataModel.gameItemData[model.id] = model
            // TODO: this fix some 2 test but let shown the wrong image / previous ones
//            itemDataModel.gameItems.removeAll(where: { $0 == model.id })
//            itemDataModel.gameItems.append(model.id)
            return
        }
        if let orignal = self.itemSync(for: model.id, noGame: true) {
            let resort = orignal.name != model.name
            if orignal.replace(with: model) {
                try? dataControllable?.replaceSync(id: orignal.id, with: orignal.copy())
                if resort {
                    resortItem(changed: orignal)
                }
            }
        } else {
            if isInsert {
                try? dataControllable?.replaceSync(id: model.id, with: model.copy())
            }
            setModel(with: model)
            insertIntoItems(model: model)
        }
    }
}

// MARK: - ImportControllable

public extension ItemControllable {
    func decode(data: Data, with decoder: JSONDecoder, version: Int) throws -> Model {
        // default ignore any version numbers. Later a module can handle older version differently.
        try decoder.decode(Model.self, from: data)
    }

    @MainActor func merge(with model: ModelType, forceMerge: Bool = false) async -> ModelType? {
        guard forceMerge == true || itemDataModel.isGameMode == false else { return model }
        guard let model = model as? Model, let current = await self.item(for: model.id) else { return model }
        if model.isSame(current) {
            return nil
        }
        return model.merge(current)
    }
    
    func reset(fileUrl: FileUrl?, item: inout any ItemDataAccessable) async {
        if let oldFileUlr = item.fileUrl {
            await cacheControllable?.remove(itemId: oldFileUlr.fileId)
        }
        item.fileUrl = fileUrl
    }
}

// MARK: - SyncDataController

public extension ItemControllable {
    func resetData() async {
        let allItemIds = await itemDataModel.items

        // Clean up cache and internal state for each item
        for id in allItemIds {
            guard let item = await self.item(for: id) else { continue }

            // Remove cache for all entries
            let entries = item.entries
            for entry in entries {
                await cacheControllable?.remove(itemId: entry.id)
            }

            // Will not remove files on reset Database
            // Remove file cache if exists
            if let fileUrl = item.fileUrl {
                await cacheControllable?.remove(itemId: id)
                fileUrlDataController?.removeBookmarks(fileId: fileUrl.fileId)
            }

            // Reset internal state
            await itemDataModel.resetModel(id: item.id)
        }

        // Batch delete all items from Core Data for better performance
        try? await dataControllable?.batchDelete(ids: allItemIds)
    }

    func save() async {
        try? await dataControllable?.save()
    }

    func updates(_ models: [ModelType]) async {
        let sortedModels = models.compactMap { $0 as? Model }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let deletedIds = await itemDataModel.items.filter { id in !sortedModels.contains { $0.id == id } }
        for id in deletedIds {
            await delete(itemId: id)
        }
        var updatedItems: [UUID] = []
        for item in sortedModels {
            await setModel(with: item)
            updatedItems.append(item.id)
        }
        await itemDataModel.resetItems(updatedItems)
    }
}

// MARK: - Viewer

public extension ItemControllable {
    @MainActor func children(itemId: UUID) -> [Model] {
        guard let parent = itemSync(for: itemId) else { return [] }
        return parent.entries.map(\.childId).compactMap {
            itemSync(for: $0)
        }
    }
    
    @MainActor func subChildren(itemId: UUID, entryId: UUID?) -> [Model] { return [] }
        
    func item(for itemId: UUID) async -> Model? {
        await itemDataModel.item(for: itemId) as? Model
    }

    func item(for itemId: UUID, fullIds: [UUID], partialIds: [UUID]) async -> Model? {
        guard let model = await itemDataModel.item(for: itemId) as? Model else { return nil }
        guard partialIds.contains(itemId) else { return model }
        let partial = model.copy()
        partial.entries = model.entries.filter {
            partialIds.contains($0.childId) || fullIds.contains($0.childId)
        }
        return partial
    }

    func item(for itemId: UUID, version: Int) async -> Model? {
        let item = await self.item(for: itemId)
        guard version != 0, let item else { return item }
        return item.version == version ? item : nil
    }
    
    @MainActor func itemSync(for itemId: UUID, noGame: Bool = false) -> Model? {
        itemDataModel.item(for: itemId, noGame: noGame) as? Model
    }

    @MainActor func itemOrEmpty(for itemId: UUID) -> Model {
        guard let item = self.itemSync(for: itemId) else { return Model.empty(itemId) }
        return item
    }
    
    @MainActor func nameSync(itemId: UUID) -> String {
        guard let item = self.itemSync(for: itemId) else { return "" }
        return item.name
    }
    
    func loadableUrl(itemId: UUID) async -> URL? {
        guard let fileUrl = await self.item(for: itemId)?.fileUrl else { return nil }
        return await fileUrlDataController?.url(for: fileUrl, action: { $0 })
    }
}

// MARK: - Compact Text

public extension ItemControllable {
    /// Returns a compact plain-text representation of the item for AI extraction.
    ///
    /// Default behaviour:
    /// - **Folder / collection** (`specialCategory`): lists visible child names prefixed with "- ".
    /// - **Regular item**: formats as `"<ModuleTitle>: <name>\n\n- entry1\n- entry2…"`.
    ///   Entries with `isGroupHidden` (e.g. MapRPG hex-grid entries) are excluded.
    ///   Returns `""` when the item has no entries.
    /// - Returns `""` when the item is not found.
    ///
    /// Modules that need custom formatting (e.g. PdfRPG loading file content) can override this.
    func compactText(for itemId: UUID) async -> String {
        guard let item = await self.item(for: itemId) else { return "" }
        var lines: [String] = []
        if item.specialCategory {
            for entry in item.entries where !entry.isGroupHidden {
                if let child = await self.item(for: entry.childId), !child.name.isEmpty {
                    lines.append("- \(child.name)")
                }
            }
        } else {
            let visibleEntries = item.entries.filter { !$0.isGroupHidden }
            guard !visibleEntries.isEmpty else { return "" }
            if !item.name.isEmpty {
                lines.append("\(config.module.title): \(item.name)")
                lines.append("")
            }
            for entry in visibleEntries {
                lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Intern

private extension ItemControllable {
    @MainActor func setModel(with model: ModelType) {
        guard let model = model as? Model else { return }
        itemDataModel.setItem(id: model.id, item: model)
    }

    @MainActor func resortItem(changed model: Model) {
        guard itemDataModel.removeItem(itemId: model.id) else { return }
        insertIntoItems(model: model)
    }

    @MainActor func insertIntoItems(model: Model) {
        var foundIndex: Int?
        for (index, itemId) in itemDataModel.items.enumerated() {
            if itemSync(for: itemId, noGame: true)?.name.localizedCompare(model.name) == .orderedDescending {
                foundIndex = index
                break
            }
        }
        itemDataModel.insert(itemId: model.id, at: foundIndex)
    }
}
