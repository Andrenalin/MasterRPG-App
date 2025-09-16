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
            do {
                let oldModel = try decoder.decode(PdfModel.self, from: data)
                return ConverterController.convert(old: oldModel)
            } catch {
                print(error)
                fatalError()
            }
        }
    }

    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        var externalData: Data? = nil
        if let pdfModel = model(for: id)?.codableModel {
            externalData = try encoder.encode(pdfModel)
        }
        let model = itemDataCodableModel(for: id, externalData: externalData)
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

extension ItemController {
    @MainActor func model(for itemId: UUID?) -> PdfDataModel? {
        guard let itemId else { return nil }
        let predicate = #Predicate<PdfDataModel> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<PdfDataModel>(predicate: predicate)
        let models: [PdfDataModel] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let item = PdfDataModel(itemId: itemId)
            container.mainContext.insert(item)
            try? container.mainContext.save()
            return item
        }
        return model
    }
}
