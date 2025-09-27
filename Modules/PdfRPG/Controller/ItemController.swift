// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.itemCacheModel = ItemCacheModel()
        self.container = container
        self.module = module
        self.modelCacheModel = ModelCacheModel()
    }
    
    let itemCacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .bookshelf
    let module: NetworkModules
    let modelCacheModel: ModelCacheModel<PdfDataModel>
}

extension ItemController: ModelCacheControllable {}

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(PdfModel.self, from: data)
                return ConverterController.convert(old: oldModel)
            } catch {
                print(error)
                fatalError()
            }
        }
    }

    @MainActor func itemDataCodableModel(id: UUID) -> ItemDataCodableModel? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let ownModel = model(for: id)?.codableModel {
            externalData = try? encoder.encode(ownModel)
        }
        return itemDataCodableModel(for: id, externalData: externalData)
    }
    
    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        guard let model = itemDataCodableModel(id: id) else { return nil }
        let encoder = JSONEncoder()
        return try encoder.encode(model)
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newPdf = try? decoder.decode(PdfDataModel.PdfDataModelCodable.self, from: data) else { return }
        if let oldPdf = model(for: id) {
            oldPdf.replace(newPdf)
        } else {
            let newModel = PdfDataModel(newPdf)
            container.mainContext.insert(newModel)
        }
    }
    
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.pdf.token)
    }
}
