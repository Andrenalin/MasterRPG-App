// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.cacheModel = ItemCacheModel()
        self.container = container
        self.module = module
    }
    let cacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
    let module: NetworkModules
}

// MARK: - Import Controller

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(TableModel.self, from: data)
                return ConverterController.convert(old: oldModel, itemController: self)
            } catch {
                print(error)
                fatalError()
            }
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

    @MainActor func replaceLinks(model: TableDataModel) {
        let controller = LinkRegisterController(container: container)
        model.entries.forEach { entry in
            let updatedContent = controller.verifyLinks(in: entry.content, destinationItemId: entry.itemId, destinationEntryId: entry.entryId, destinationModule: .table)
            entry.content = updatedContent
        }
    }
}

extension ItemController {
    func clean() {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<TableDataModel> { $0.displayState == 2 }
        let fetchDesc = FetchDescriptor<TableDataModel>(predicate: predicate)
        guard let models = try? modelContext.fetch(fetchDesc) else { return }
        for model in models {
            modelContext.delete(model)
        }
        cleanDeleted()
    }

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
