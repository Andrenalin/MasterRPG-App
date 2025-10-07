// @copyright André Trettin

import Foundation
import os.log
import SwiftData

public protocol ImportDataControllable: Sendable {
    var container: ModelContainer { get }
    
    @MainActor func item(for id: UUID) -> ItemDataModel?
    
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel
    func merge(with model: ItemDataCodableModel) async -> ItemDataCodableModel
    @MainActor func replace(model: ItemDataCodableModel?, isInsert: Bool, shouldRepairLinks: Bool)
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool)
}

public extension ImportDataControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        return try decoder.decode(ItemDataCodableModel.self, from: data)
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
}
