// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .bookshelf
}

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            let oldModel = try decoder.decode(PdfModel.self, from: data)
            return ConverterController.convert(old: oldModel)
        }
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        let pdfModels = models(for: id)
        if !pdfModels.isEmpty {
            let codableModels = pdfModels.map { $0.codableModel }
            externalData = try encoder.encode(codableModels)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
        return try encoder.encode(model)
    }
    
    @MainActor func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let data else { return }
        let decoder = JSONDecoder()
        guard let newPdfModels = try? decoder.decode([PdfDataModel.PdfDataModelCodable].self, from: data) else { return }
        let existingModels = models(for: id)
        
        // Remove existing models
        for model in existingModels {
            container.mainContext.delete(model)
        }
        
        // Add new models
        for codableModel in newPdfModels {
            let newModel = PdfDataModel(codableModel)
            container.mainContext.insert(newModel)
        }
    }
    
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.pdf.token)
    }
}

extension ItemController {
    @MainActor func models(for itemId: UUID) -> [PdfDataModel] {
        let predicate = #Predicate<PdfDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<PdfDataModel>(predicate: predicate)
        return (try? container.mainContext.fetch(fetchDesc)) ?? []
    }
}
