// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
}

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            let oldModel = try decoder.decode(TableModel.self, from: data)
            return ConverterController.convert(old: oldModel)
        }
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let tableModel = model(for: id)?.codableModel {
            externalData = try encoder.encode(tableModel)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
        return try encoder.encode(model)
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newTable = try? decoder.decode(TableDataModel.TableDataModelCodable.self, from: data) else { return }
        if let oldTable = model(for: id) {
            oldTable.replace(newTable)
        } else {
            let newModel = TableDataModel(newTable)
            container.mainContext.insert(newModel)
        }
    }
}

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> TableDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<TableDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<TableDataModel>(predicate: predicate)
        let models: [TableDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let item = TableDataModel(itemId: itemId)
            container.mainContext.insert(item)
            try? container.mainContext.save()
            return item
        }
        return model
    }
}
