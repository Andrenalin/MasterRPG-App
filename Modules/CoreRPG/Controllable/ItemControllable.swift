// @copyright André Trettin

import Foundation
import Observation

public enum GameMutationPolicy: Equatable, Sendable {
    case memoryOnly
    case persist
}

/// Captures persistence errors from legacy edit-controller repair operations.
///
/// Most editor call sites intentionally keep their historical best-effort behaviour.
/// External import installs this reporter only while running its repair pass so a
/// swallowed `replaceSync` error can still abort the transaction and be rolled back.
@MainActor
final class ItemPersistenceFailureReporter {
    private var firstError: (any Error)?

    func record(_ error: any Error) {
        if firstError == nil {
            firstError = error
        }
    }

    func rethrowRecordedError() throws {
        if let firstError {
            throw firstError
        }
    }
}

enum ItemPersistenceFailureScope {
    @TaskLocal static var reporter: ItemPersistenceFailureReporter?
}

enum ItemTransactionMutationError: LocalizedError {
    case incompatibleModel

    var errorDescription: String? {
        switch self {
        case .incompatibleModel:
            "The model is incompatible with this item controller."
        }
    }
}

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistable & Identifiable & Equatable & Hashable & Codable & ModelType
    
    var cacheControllable: ImageCacheControllable? { get }
    var config: ModuleConfigurable { get }
    var collectionCategory: ItemListCategory { get }
    @MainActor var dataControllable: (any DataPersistenceControllable)? { get }
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
        await CloudKitOperationCounter.shared.recordOperation(
            function: "ItemControllable.addNew(type:\(type))",
            file: "ItemControllable.swift"
        )
        
        var model = Model.empty.copy()
        model.category = type
        try? await dataControllable?.replace(id: model.id, with: model)
        resetModel(with: model)
        await save()
        return model.id
    }

    @MainActor func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }
    
    @MainActor func delete(itemId: UUID, withFileData: Bool = true, withDatabase: Bool = true) async {
        
        guard let item = await self.item(for: itemId) else { return }
        let entries = item.entries
        for entry in entries {
            await cacheControllable?.remove(itemId: entry.id)
        }
        
        if withDatabase {
            await CloudKitOperationCounter.shared.recordOperation(
                function: "ItemControllable.delete(itemId:withFileData:\(withFileData))",
                file: "ItemControllable.swift"
            )
            do {
                try await dataControllable?.delete(id: item.id)
            } catch {
                ItemPersistenceFailureScope.reporter?.record(error)
            }
        }
        if let fileUrlDataController, let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            if withFileData {
                fileUrlDataController.delete(fileUrl)
            }
        }
        
        itemDataModel.resetModel(id: item.id)
        itemDataModel.publishContentWidgetSnapshot()
    }
    
    @MainActor func isEqual(with other: ModelType) -> Bool {
        guard let other = other as? Model, let second = self.itemSync(for: other.id) else { return false }
        return second.isEqual(other: other)
    }
    
    @MainActor func replace(model: ModelType?, isInsert: Bool, forceSave: Bool = false) {
        guard let model = model as? Model else { return }
        if itemDataModel.isGameMode == true && forceSave == false {
            replaceInGameMemory(model: model)
            return
        }
        
        if let original = self.itemSync(for: model.id, noGame: true) {
            let resort = original.name != model.name
            if original.replace(with: model) {
                do {
                    try dataControllable?.replaceSync(id: original.id, with: original.copy())
                } catch {
                    ItemPersistenceFailureScope.reporter?.record(error)
                }
                if resort {
                    resortItem(changed: original)
                }
                itemDataModel.publishContentWidgetSnapshot()
            }
            syncGameMemoryIfLoaded(with: original)
        } else {
            if isInsert {
                do {
                    try dataControllable?.replaceSync(id: model.id, with: model.copy())
                } catch {
                    ItemPersistenceFailureScope.reporter?.record(error)
                }
            }
            resetModel(with: model)
            syncGameMemoryIfLoaded(with: model)
        }
    }

    /// Keeps a live game session's in-memory snapshot of this item consistent with
    /// a just-persisted write.
    ///
    /// `ItemDataModel.item(for:)` always prefers `gameItemData` over the permanent
    /// store whenever an entry exists there, regardless of `isGameMode` — so a
    /// `forceSave: true` edit (e.g. from the standalone item editor while a game is
    /// running) that only updated the permanent store would otherwise stay invisible
    /// to every reader — the editor's own re-render, the live game view, and any
    /// other view — for as long as this item remains loaded into game memory, and
    /// even after the game ends if `gameItemData` is never cleared for it.
    ///
    /// Mutates the existing game-memory instance in place (like the permanent-store
    /// branch above does via `original.replace(with: model)`) rather than replacing
    /// it with a fresh copy: any view or model already holding a reference to that
    /// exact `@Observable` instance — e.g. a live game view rendered from a
    /// different `SheetRootModel` — must see the change through its own reference,
    /// not just through a fresh dictionary lookup.
    @MainActor private func syncGameMemoryIfLoaded(with model: Model) {
        guard let gameItem = itemDataModel.gameItemData[model.id] as? Model else { return }
        _ = gameItem.replace(with: model)
    }

    /// Replaces an imported item and keeps the cross-module link register in sync with
    /// the imported value. Import paths bypass `EditControllable.saveChanges`, so they
    /// must use this method instead of plain `replace(model:isInsert:forceSave:)`.
    @MainActor func replaceImportedModel(model: ModelType?, isInsert: Bool, forceSave: Bool = false) {
        guard let model = model as? Model else { return }

        if let previous = itemSync(for: model.id)?.copy() {
            let changes = model.changedLinkRegisterModels(oldValue: previous)
            linkRegisterController.deregister(links: changes.removed)
            linkRegisterController.register(links: changes.added)
        } else {
            linkRegisterController.register(links: model.linkRegisterModels)
        }

        replace(model: model, isInsert: isInsert, forceSave: forceSave)
    }

    /// Stages one exact model snapshot for an external-import transaction and
    /// surfaces persistence errors to the caller. This deliberately does not
    /// change the best-effort behaviour of the general editor API above.
    @MainActor func replaceForExternalImport(
        model: any ModelType,
        isInsert: Bool
    ) throws {
        guard let model = model as? Model else {
            throw ItemTransactionMutationError.incompatibleModel
        }

        let snapshot = model.copy()
        let existing = itemSync(for: snapshot.id, noGame: true)
        if existing != nil || isInsert {
            try dataControllable?.replaceSync(id: snapshot.id, with: snapshot)
        }

        if let existing {
            let needsResort = existing.name != snapshot.name
            setModel(with: snapshot)
            if needsResort {
                resortItem(changed: snapshot)
            }
        } else {
            resetModel(with: snapshot)
        }
    }

    /// Removes an item as part of external-import rollback while keeping the
    /// binary intact. Database staging happens before the in-memory removal so a
    /// thrown error never masquerades as a successful rollback.
    @MainActor func deleteForExternalImport(itemId: UUID) async throws {
        guard let item = itemSync(for: itemId, noGame: true) else { return }
        try await dataControllable?.delete(id: item.id)

        for entry in item.entries {
            await cacheControllable?.remove(itemId: entry.id)
        }
        if let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            fileUrlDataController?.removeBookmarks(fileId: fileUrl.fileId)
        }
        itemDataModel.resetModel(id: item.id)
    }

    /// Exact copies of the current library models used to cover repair effects
    /// that can reach parents or children outside the selected import batch.
    @MainActor func externalImportSnapshots(excluding excludedIDs: Set<UUID>) -> [any ModelType] {
        itemDataModel.items.compactMap { itemId -> (any ModelType)? in
            guard !excludedIDs.contains(itemId),
                  let item = itemSync(for: itemId, noGame: true) else { return nil }
            return item.copy()
        }
    }

    @MainActor func replaceForGame(model: ModelType?, isInsert: Bool, policy: GameMutationPolicy) {
        switch policy {
        case .memoryOnly:
            replaceInGameMemory(model: model)
        case .persist:
            replace(model: model, isInsert: isInsert, forceSave: true)
        }
    }

    /// Mutates the existing game-memory instance in place when this item is
    /// already loaded (preserving its object identity, like
    /// `syncGameMemoryIfLoaded` above does for the reverse direction) rather
    /// than replacing it with the incoming reference: any view or model
    /// already holding a reference to that exact `@Observable` instance must
    /// see the change through its own reference, not just through a fresh
    /// dictionary lookup.
    @MainActor func replaceInGameMemory(model: ModelType?) {
        guard let model = model as? Model else { return }
        if let existing = itemDataModel.gameItemData[model.id] as? Model {
            _ = existing.replace(with: model)
        } else {
            itemDataModel.gameItemData[model.id] = model
        }
    }

    @MainActor func mergeUpdates(model: ModelType) {
        guard let model = model as? Model, let original = self.itemSync(for: model.id, noGame: true) else { return }
        let resort = original.name != model.name
        if original.replace(with: model) {
            if resort {
                resortItem(changed: original)
            }
            itemDataModel.publishContentWidgetSnapshot()
        }
    }
}

// MARK: - ImportControllable

public extension ItemControllable {
    @MainActor func decode(data: Data, with decoder: JSONDecoder, version: Int) throws -> Model {
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
    
    @MainActor func reset(fileUrl: FileUrl?, item: inout any ItemDataAccessable) async {
        if let oldFileUlr = item.fileUrl {
            await cacheControllable?.remove(itemId: oldFileUlr.fileId)
        }
        item.fileUrl = fileUrl
    }
}

// MARK: - SyncDataController

public extension ItemControllable {
    @MainActor func resetData() async {
        let allItemIds = itemDataModel.items

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
            itemDataModel.resetModel(id: item.id)
        }
        itemDataModel.publishContentWidgetSnapshot()

        // Batch delete all items from Core Data for better performance
        try? await dataControllable?.batchDelete(ids: allItemIds)
    }

    func save() async {
        try? await dataControllable?.save()
        await AppIntentContentInvalidator.invalidate()
    }

    func flushPendingOperations() async {
        try? await dataControllable?.flushPendingOperations()
    }

    @MainActor func updates(_ models: [ModelType]) async {
        let sortedModels = models.compactMap { $0 as? Model }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let deletedIds = itemDataModel.items.filter { id in !sortedModels.contains { $0.id == id } }
        for id in deletedIds {
            await delete(itemId: id)
        }
        var updatedItems: [UUID] = []
        for item in sortedModels {
            setModel(with: item)
            updatedItems.append(item.id)
        }
        itemDataModel.resetItems(updatedItems)
        itemDataModel.publishContentWidgetSnapshot()
    }
    
    @MainActor func resetModel(with model: ModelType?) {
        guard let model = model as? Model else { return }
        setModel(with: model)
        insertIntoItems(model: model)
        itemDataModel.publishContentWidgetSnapshot()
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

    @MainActor func item(for itemId: UUID, fullIds: [UUID], partialIds: [UUID]) async -> Model? {
        guard let model = itemDataModel.item(for: itemId) as? Model else { return nil }
        guard partialIds.contains(itemId) else { return model }
        let partial = model.copy()
        partial.entries = model.entries.filter {
            partialIds.contains($0.childId) || fullIds.contains($0.childId)
        }
        return partial
    }

    @MainActor func item(for itemId: UUID, version: Int) async -> Model? {
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
    
    @MainActor func loadableUrl(itemId: UUID) async -> URL? {
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
    @MainActor func compactText(for itemId: UUID) async -> String {
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
    @MainActor func setModel(with model: Model) {
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
