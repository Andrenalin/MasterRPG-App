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
}

@MainActor @Observable final class ImportReviewItemModel: Identifiable, Hashable {
    nonisolated static func == (lhs: ImportReviewItemModel, rhs: ImportReviewItemModel) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(id: UUID, kind: ImportReviewItemModel.ChangeKind, existingStatus: String, importedStatus: String, mergedStatus: String, itemModel: SingleItemImportModel) {
        self.id = id
        self.kind = kind
        self.existingStatus = existingStatus
        self.importedStatus = importedStatus
        self.mergedStatus = mergedStatus
        self.itemModel = itemModel
    }
    
    enum ChangeKind: String, CaseIterable, Hashable {
        case added = "Added"
        case different = "Different"
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

    var hasBlockingReference: Bool {
        itemModel.references.contains { !$0.isResolved }
    }
}

@MainActor @Observable final class ImportReviewModel {
    var modules: [ImportReviewModule]
    var selectedModuleID: ImportReviewModule.ID?
    var selectedItemID: ImportReviewItemModel.ID?

    init(modules: [ImportReviewModule]) {
        self.modules = modules
        self.selectedModuleID = modules.first?.id
        self.selectedItemID = modules.first?.reviewItems.first?.id
    }

    var selectedModule: ImportReviewModule? {
        modules.first { $0.id == selectedModuleID }
    }

    var selectedItem: ImportReviewItemModel? {
        selectedModule?.reviewItems.first { $0.id == selectedItemID }
    }

    func select(moduleID: ImportReviewModule.ID) {
        selectedModuleID = moduleID
        selectedItemID = modules.first { $0.id == moduleID }?.reviewItems.first?.id
    }

    func select(itemID: ImportReviewItemModel.ID) {
        selectedItemID = itemID
    }

    func selectDependency(_ reference: SingleReviewReference) {
        for module in modules {
            if let item = module.reviewItems.first(where: { $0.id == reference.id }) {
                selectedModuleID = module.id
                selectedItemID = item.id
                return
            }
        }
    }

    func setDecision(_ decision: SingleReviewDecision, for itemID: ImportReviewItemModel.ID) {
        itemModel(for: itemID)?.applyItemDecision(decision)
    }

    func setPropertyDecision(_ decision: SingleReviewDecision, propertyID: UUID, itemID: ImportReviewItemModel.ID) {
        itemModel(for: itemID)?.setPropertyDecision(decision, propertyID: propertyID)
    }

    private func itemModel(for itemID: ImportReviewItemModel.ID) -> SingleItemImportModel? {
        for module in modules {
            if let item = module.reviewItems.first(where: { $0.id == itemID }) {
                return item.itemModel
            }
        }
        return nil
    }
}

