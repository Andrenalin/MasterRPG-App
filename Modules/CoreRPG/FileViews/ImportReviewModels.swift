// @copyright André Trettin

import SwiftUI

@MainActor @Observable final class ImportReviewModule: Identifiable, Hashable {
    nonisolated static func == (lhs: ImportReviewModule, rhs: ImportReviewModule) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(id: NetworkModules, reviewItems: [ImportReviewItemModel]) {
        self.id = id
        self.reviewItems = reviewItems
    }

    let id: NetworkModules
    var reviewItems: [ImportReviewItemModel]

    var name: String { id.title }
    var addedItems: [ImportReviewItemModel] { reviewItems.filter { $0.kind == .added } }
    var changedItems: [ImportReviewItemModel] { reviewItems.filter { $0.kind == .different && !$0.isDeletion } }
    /// Local items the file does not contain, listed apart from real changes: choosing the
    /// imported version deletes them. See CODE_AUDIT_Folder §5.9.
    var notInImportItems: [ImportReviewItemModel] { reviewItems.filter(\.isDeletion) }
    var blockedReferenceCount: Int { reviewItems.filter(\.hasBlockingReference).count }
}

@MainActor @Observable final class ImportReviewItemModel: Identifiable, Hashable {
    nonisolated static func == (lhs: ImportReviewItemModel, rhs: ImportReviewItemModel) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(id: UUID, kind: ImportReviewItemModel.ChangeKind, existingStatus: String, importedStatus: String, mergedStatus: String, itemModel: SingleItemImportModel, isDeletion: Bool = false) {
        self.id = id
        self.kind = kind
        self.existingStatus = existingStatus
        self.importedStatus = importedStatus
        self.mergedStatus = mergedStatus
        self.itemModel = itemModel
        self.isDeletion = isDeletion
    }

    enum ChangeKind: String, CaseIterable, Hashable {
        case added = "Added"
        case different = "Different"

        var title: String {
            switch self {
            case .added: String(localized: "Added", bundle: .module)
            case .different: String(localized: "Changed", bundle: .module)
            }
        }

        var systemImage: String {
            switch self {
            case .added: "plus.circle.fill"
            case .different: "arrow.triangle.2.circlepath.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .added: .green
            case .different: .orange
            }
        }
    }

    let id: UUID
    var name: String {
        itemModel.name
    }
    var summary: String {
        itemModel.description
    }

    let kind: ChangeKind
    let existingStatus: String
    let importedStatus: String
    let mergedStatus: String
    let itemModel: SingleItemImportModel
    /// Local item missing from the import stream; decision `.imported` deletes it on apply.
    let isDeletion: Bool

    var hasBlockingReference: Bool {
        itemModel.references.contains { !$0.isResolved }
    }
}

@MainActor @Observable final class ImportReviewModel {
    var modules: [ImportReviewModule]
    var selectedModuleId: ImportReviewModule.ID?
    var selectedItemId: ImportReviewItemModel.ID?

    init(modules: [ImportReviewModule]) {
        self.modules = modules
        self.selectedModuleId = modules.first?.id
        self.selectedItemId = modules.first?.reviewItems.first?.id
    }

    var selectedModule: ImportReviewModule? {
        modules.first { $0.id == selectedModuleId }
    }

    var selectedItem: ImportReviewItemModel? {
        selectedModule?.reviewItems.first { $0.id == selectedItemId }
    }

    var sheetMemorySignature: String {
        modules.flatMap { module in
            module.reviewItems.map { item in
                "\(module.id.rawValue):\(item.id.uuidString):\(item.itemModel.decisionSignature)"
            }
        }
        .joined(separator: "|")
    }

    func select(moduleId: ImportReviewModule.ID) {
        selectedModuleId = moduleId
        selectedItemId = modules.first { $0.id == moduleId }?.reviewItems.first?.id
    }

    func select(itemId: ImportReviewItemModel.ID) {
        selectedItemId = itemId
    }

    /// Model of a linked item for display: prefers the import batch (imported items are
    /// not in the database yet), then falls back to the database.
    func displayModel(for destination: ItemRowModel, preferImported: Bool, rootManager: RootManager?) -> (any ItemDataAccessible)? {
        if let pending = modules.first(where: { $0.id == destination.typeId })?
            .reviewItems.first(where: { $0.id == destination.itemId }) {
            let item = pending.itemModel.item
            return preferImported ? (item.imported ?? item.merged) : (item.existing ?? item.merged)
        }
        return rootManager?.rootModel(for: destination.typeId)?.itemControllable.itemSync(for: destination.itemId)
    }

    func sheetMemory() -> ReviewSheetMemory {
        sheetMemory(overriding: nil)
    }

    func sheetMemory(
        overriding itemId: UUID,
        module: NetworkModules,
        decision: SingleReviewDecision
    ) -> ReviewSheetMemory {
        sheetMemory(overriding: (itemId, module, decision))
    }

    private func sheetMemory(
        overriding override: (itemId: UUID, module: NetworkModules, decision: SingleReviewDecision)?
    ) -> ReviewSheetMemory {
        var items: [NetworkModules: [UUID: any ItemDataAccessible]] = [:]
        var hiddenItemIds: [NetworkModules: Set<UUID>] = [:]

        for module in modules {
            for item in module.reviewItems {
                let overriddenDecision: SingleReviewDecision?
                if let override, override.itemId == item.id, override.module == module.id {
                    overriddenDecision = override.decision
                } else {
                    overriddenDecision = nil
                }
                let decision = overriddenDecision ?? item.itemModel.decision

                if (item.isDeletion && decision == .imported) ||
                    (item.kind == .added && decision == .existing) {
                    hiddenItemIds[module.id, default: []].insert(item.id)
                    continue
                }

                if let overriddenDecision {
                    items[module.id, default: [:]][item.id] = item.itemModel.materializedItem(for: overriddenDecision)
                } else {
                    items[module.id, default: [:]][item.id] = item.itemModel.materializedItem()
                }
            }
        }

        return ReviewSheetMemory(items: items, hiddenItemIds: hiddenItemIds)
    }

    /// Builds the reference list for every review item once all items are imported.
    /// The imported items are not in the database yet, so each module's LinkControllable
    /// extracts the links directly from the imported item, used as link source.
    func resolveReferences(rootManager: RootManager) {
        var pendingItems: [UUID: ImportReviewItemModel] = [:]
        for module in modules {
            for item in module.reviewItems {
                pendingItems[item.id] = item
            }
        }

        for module in modules {
            guard let linkControllable = rootManager.rootModel(for: module.id)?.linkControllable else { continue }
            for item in module.reviewItems {
                guard let imported = item.itemModel.item.imported else { continue }
                var seenDestinations: Set<ItemRowModel> = []
                item.itemModel.references = linkControllable.links(for: imported).compactMap { link in
                    let destination = link.destination
                    guard destination.typeId != .none, !seenDestinations.contains(destination) else { return nil }
                    seenDestinations.insert(destination)
                    guard let destinationLinks = rootManager.rootModel(for: destination.typeId)?.linkControllable else { return nil }

                    let existsInLibrary = destinationLinks.validateLink(itemId: destination.itemId, entryId: destination.entryId)
                    let pendingItem = pendingItems[destination.itemId]
                    var itemName = link.name
                    if itemName.isEmpty {
                        itemName = pendingItem?.name ?? destinationLinks.name(for: destination.itemId, entryId: destination.entryId)
                    }
                    return SingleReviewReference(itemName: itemName, destination: destination, existsInLibrary: existsInLibrary, pendingItem: pendingItem)
                }
            }
        }
    }

    func setDecision(_ decision: SingleReviewDecision, for itemId: ImportReviewItemModel.ID) {
        itemModel(for: itemId)?.applyItemDecision(decision)
    }

    func setPropertyDecision(_ decision: SingleReviewDecision, propertyId: UUID, itemId: ImportReviewItemModel.ID) {
        itemModel(for: itemId)?.setPropertyDecision(decision, propertyId: propertyId)
    }

    private func itemModel(for itemId: ImportReviewItemModel.ID) -> SingleItemImportModel? {
        for module in modules {
            if let item = module.reviewItems.first(where: { $0.id == itemId }) {
                return item.itemModel
            }
        }
        return nil
    }
}
